import * as FileSystem from 'expo-file-system/legacy';
import { unzip } from 'react-native-zip-archive';

export interface TocItem {
  label: string;
  href: string;
  chapterIndex: number;
}

export interface Chapter {
  id: string;
  href: string;
  title: string;
}

export interface ParsedEpub {
  chapters: Chapter[];
  toc: TocItem[];
  basePath: string; // extracted dir with trailing slash
}

// ── Tiny XML helpers (no DOM on RN) ──
const attr = (xml: string, tag: string, attribute: string): string => {
  const re = new RegExp(`<${tag}[^>]*\\s${attribute}=["']([^"']+)["']`, 'i');
  return xml.match(re)?.[1] ?? '';
};

const allAttrs = (xml: string, tag: string, attribute: string): string[] => {
  const re = new RegExp(`<${tag}[^>]*\\s${attribute}=["']([^"']+)["']`, 'gi');
  return [...xml.matchAll(re)].map(m => m[1]);
};

const tagContent = (xml: string, tag: string): string =>
  xml.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i'))?.[1] ?? '';

export async function extractAndParseEpub(
  epubPath: string,
  cacheKey: string,
): Promise<ParsedEpub> {
  const extractDir = `${FileSystem.cacheDirectory}epub_${cacheKey}/`;

  // Skip extraction if already cached
  const info = await FileSystem.getInfoAsync(extractDir);
  if (!info.exists) {
    await unzip(epubPath, extractDir);
  }

  // 1. Find OPF path from META-INF/container.xml
  const containerXml = await FileSystem.readAsStringAsync(
    `${extractDir}META-INF/container.xml`,
  );
  const opfRelPath = attr(containerXml, 'rootfile', 'full-path');
  if (!opfRelPath) {
    throw new Error('Could not find OPF path in container.xml');
  }
  const opfDir = opfRelPath.includes('/')
    ? opfRelPath.substring(0, opfRelPath.lastIndexOf('/') + 1)
    : '';

  // 2. Parse OPF
  const opfXml = await FileSystem.readAsStringAsync(`${extractDir}${opfRelPath}`);

  // Build manifest: id → { href, mediaType }
  const manifestMatches = [...opfXml.matchAll(
    /<item\s[^>]*id=["']([^"']+)["'][^>]*href=["']([^"']+)["'][^>]*media-type=["']([^"']+)["'][^>]*/gi,
  )];
  const manifest: Record<string, { href: string; mediaType: string }> = {};
  for (const m of manifestMatches) {
    manifest[m[1]] = { href: m[2], mediaType: m[3] };
  }

  // Also match with attributes in different order
  const manifestMatches2 = [...opfXml.matchAll(
    /<item\s[^>]*href=["']([^"']+)["'][^>]*id=["']([^"']+)["'][^>]*media-type=["']([^"']+)["'][^>]*/gi,
  )];
  for (const m of manifestMatches2) {
    if (!manifest[m[2]]) {
      manifest[m[2]] = { href: m[1], mediaType: m[3] };
    }
  }

  // Spine: ordered item idrefs
  const spineContent = tagContent(opfXml, 'spine');
  const spineIds = allAttrs(spineContent, 'itemref', 'idref');

  const chapters: Chapter[] = [];
  for (let i = 0; i < spineIds.length; i++) {
    const id = spineIds[i];
    const item = manifest[id];
    if (item && item.mediaType.includes('html')) {
      chapters.push({
        id,
        href: `${extractDir}${opfDir}${item.href}`,
        title: `Chapter ${i + 1}`,
      });
    }
  }

  // 3. Try to get chapter titles from manifest or TOC
  // Parse manifest items with title
  const titleMatches = [...opfXml.matchAll(
    /<item\s[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/item>/gi,
  )];
  for (const tm of titleMatches) {
    const href = tm[1];
    const titleMatch = tm[0].match(/<dc:title>([^<]+)<\/dc:title>/i);
    if (titleMatch) {
      const ch = chapters.find(c => c.href.includes(href));
      if (ch) ch.title = titleMatch[1];
    }
  }

  // 4. Parse NCX or nav for TOC
  let toc: TocItem[] = [];

  // Try NCX (EPUB 2)
  const ncxId = attr(spineContent, 'toc', '');
  const ncxHref = ncxId ? manifest[ncxId]?.href : null;
  if (ncxHref) {
    try {
      const ncxXml = await FileSystem.readAsStringAsync(`${extractDir}${opfDir}${ncxHref}`);
      const navPoints = [...ncxXml.matchAll(
        /<navPoint[\s\S]*?<text>([\s\S]*?)<\/text>[\s\S]*?<content\s[^>]*src=["']([^"'#]+)/gi,
      )];
      toc = navPoints.map(m => {
        const label = m[1].replace(/<[^>]+>/g, '').trim();
        const srcHref = m[2];
        const fullHref = srcHref.includes('/')
          ? `${extractDir}${opfDir}${srcHref}`
          : `${extractDir}${opfDir}${srcHref}`;
        const idx = chapters.findIndex(c => {
          const chName = c.href.split('/').pop() ?? '';
          const srcName = srcHref.split('/').pop() ?? '';
          return chName === srcName || c.href.includes(srcName);
        });
        return { label, href: fullHref, chapterIndex: Math.max(0, idx) };
      });
    } catch {
      // NCX parse failed, ignore
    }
  }

  // Try nav (EPUB 3) if no NCX TOC
  if (toc.length === 0) {
    const navItem = Object.values(manifest).find(m => m.href.includes('nav') && m.mediaType.includes('html'));
    if (navItem) {
      try {
        const navHtml = await FileSystem.readAsStringAsync(`${extractDir}${opfDir}${navItem.href}`);
        const tocMatches = [...navHtml.matchAll(
          /<a[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi,
        )];
        toc = tocMatches.map(m => {
          const label = m[2].replace(/<[^>]+>/g, '').trim();
          const srcHref = m[1];
          const fullHref = `${extractDir}${opfDir}${srcHref}`;
          const idx = chapters.findIndex(c => {
            const chName = c.href.split('/').pop() ?? '';
            const srcName = srcHref.split('/').pop() ?? '';
            return chName === srcName || c.href.includes(srcName);
          });
          return { label, href: fullHref, chapterIndex: Math.max(0, idx) };
        }).filter(t => t.label && t.label.toLowerCase() !== 'table of contents');
      } catch {
        // nav parse failed
      }
    }
  }

  // Fallback: use spine as TOC
  if (toc.length === 0) {
    toc = chapters.map((c, i) => ({ label: c.title, href: c.href, chapterIndex: i }));
  }

  return { chapters, toc, basePath: `${extractDir}${opfDir}` };
}

export async function readChapterHtml(chapterHref: string, basePath: string): Promise<string> {
  let html = await FileSystem.readAsStringAsync(chapterHref);
  // Extract body content only
  const bodyMatch = html.match(/<body[^>]*>([\s\S]*)<\/body>/i);
  let body = bodyMatch ? bodyMatch[1] : html;

  // Remove script tags for security
  body = body.replace(/<script[\s\S]*?<\/script>/gi, '');
  body = body.replace(/<script\s[^>]*\/>/gi, '');

  // Fix relative image paths → absolute file:// paths
  // basePath already starts with file:// from FileSystem.cacheDirectory
  body = body.replace(
    /src=["'](?!https?:\/\/|data:|\/\/|#)([^"']+)["']/gi,
    (_, p) => `src="${basePath}${p}"`,
  );

  // Fix relative hrefs in links (keep them as-is, RenderHtml will ignore non-http)
  return body;
}
