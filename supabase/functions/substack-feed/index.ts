import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const SUBSTACK_PUBLICATION_URL = 'https://acc2049.substack.com'
const SUBSTACK_FEED_URL = `${SUBSTACK_PUBLICATION_URL}/feed`
const SUBSTACK_AUTHOR_NAME = '☭/Acc'
const SUBSTACK_AUTHOR_PROFILE_URL = 'https://substack.com/@leninistwarrior'
const EXCERPT_LENGTH = 280
const SUBSTACK_PROMO_PATTERN =
  /☭\/Acc(?:['’]|&rsquo;|&#8217;|&#x2019;)?s Substack is a reader-supported publication\.?\s*To receive new posts and support my work,?\s*consider becoming a free or paid subscriber\.?/i

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
}

const tagContent = (xml: string, tag: string): string => {
  const pattern = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`)
  const match = xml.match(pattern)
  if (!match) return ''
  return match[1]
    .replace(/^<!\[CDATA\[/, '')
    .replace(/\]\]>$/, '')
    .trim()
}

const tagAttr = (xml: string, tag: string, attr: string): string => {
  const pattern = new RegExp(`<${tag}[^>]*?\\s${attr}="([^"]*)"`)
  const match = xml.match(pattern)
  return match?.[1] || ''
}

const allTags = (xml: string, tag: string): string[] => {
  const pattern = new RegExp(`<${tag}[\\s\\S]*?</${tag}>`, 'g')
  return xml.match(pattern) || []
}

const selfClosingTags = (xml: string, tag: string): string[] => {
  const pattern = new RegExp(`<${tag}\\s[^>]*/?>`, 'g')
  return xml.match(pattern) || []
}

const removeSubstackPromoText = (value = '') =>
  value
    .replace(SUBSTACK_PROMO_PATTERN, '')
    .replace(/\s+/g, ' ')
    .trim()

const cleanSubstackContentHtml = (html = '') =>
  removeSubstackPromoText(html)
    .replace(
      /<(div|section|aside|form)[^>]*(subscribe|subscription|signup|email)[^>]*>[\s\S]*?<\/\1>/gi,
      ''
    )
    .replace(/<input[^>]*(email|Type your email)[^>]*\/?>/gi, '')
    .replace(/<button[^>]*>\s*Subscribe\s*<\/button>/gi, '')
    .trim()

const stripHtml = (html = '') =>
  removeSubstackPromoText(html)
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, ' ')
    .trim()

const slugify = (value = '') =>
  value
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 90)

const slugFromUrl = (url = '', fallbackTitle = '') => {
  try {
    const parsed = new URL(url)
    const parts = parsed.pathname.split('/').filter(Boolean)
    const postIndex = parts.indexOf('p')
    if (postIndex >= 0 && parts[postIndex + 1]) return parts[postIndex + 1]
  } catch (_error) {
    // Fall back to title slug.
  }
  return slugify(fallbackTitle)
}

const inferSubstackCategories = (title = '', excerpt = '') => {
  const haystack = [title, excerpt].join(' ').toLowerCase()

  if (/\bshort note\b/.test(haystack)) return ['Short Notes']
  if (/science|dialectic|invariance|technical|prolegomena|mathematics|physics|stem/.test(haystack)) {
    return ['Foundations of Science']
  }

  return ['Personal']
}

const extractImageUrl = (itemXml: string, contentHtml: string) => {
  const mediaUrl = tagAttr(itemXml, 'media:content', 'url') ||
    tagAttr(itemXml, 'media:thumbnail', 'url')
  if (mediaUrl) return mediaUrl

  for (const enc of selfClosingTags(itemXml, 'enclosure')) {
    const type = enc.match(/type="([^"]*)"/)?.[1] || ''
    if (type.startsWith('image/')) {
      const url = enc.match(/url="([^"]*)"/)?.[1]
      if (url) return url
    }
  }

  if (contentHtml) {
    const imgSrc = contentHtml.match(/<img[^>]+src="([^"]+)"/)?.[1]
    if (imgSrc) return imgSrc
  }

  return ''
}

const normalizeItem = (itemXml: string) => {
  const title = tagContent(itemXml, 'title') || 'Untitled Substack post'
  const url = tagContent(itemXml, 'link')
  const contentHtml = cleanSubstackContentHtml(
    tagContent(itemXml, 'content:encoded') || tagContent(itemXml, 'description')
  )
  const description = cleanSubstackContentHtml(tagContent(itemXml, 'description'))
  const excerptSource = stripHtml(description || contentHtml)
  const excerpt =
    excerptSource.length > EXCERPT_LENGTH
      ? `${excerptSource.slice(0, EXCERPT_LENGTH).trim()}...`
      : excerptSource

  const categoryMatches = allTags(itemXml, 'category')
  const categories = categoryMatches
    .map((c) => tagContent(c, 'category') || c.replace(/<\/?category[^>]*>/g, '').replace(/^<!\[CDATA\[/, '').replace(/\]\]>$/, '').trim())
    .filter(Boolean)

  return {
    id: tagContent(itemXml, 'guid') || slugFromUrl(url, title),
    title,
    slug: slugFromUrl(url, title),
    url,
    publishedAt: tagContent(itemXml, 'pubDate'),
    author: tagContent(itemXml, 'dc:creator') || SUBSTACK_AUTHOR_NAME,
    excerpt,
    contentHtml,
    imageUrl: extractImageUrl(itemXml, contentHtml),
    categories: categories.length ? categories : inferSubstackCategories(title, excerpt),
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'GET') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 405 }
    )
  }

  try {
    const feedResponse = await fetch(SUBSTACK_FEED_URL, {
      headers: {
        'Accept': 'application/rss+xml, application/xml, text/xml',
        'User-Agent': 'Marxist.info Substack feed mirror',
      },
    })

    if (!feedResponse.ok) {
      throw new Error(`Substack RSS request failed with ${feedResponse.status}`)
    }

    const xml = await feedResponse.text()
    const channelXml = tagContent(xml, 'channel')
    if (!channelXml) throw new Error('Substack RSS response could not be parsed')

    const posts = allTags(channelXml, 'item').map(normalizeItem)

    return new Response(
      JSON.stringify({
        source: {
          title: tagContent(channelXml, 'title') || '☭/Acc\'s Substack',
          url: tagContent(channelXml, 'link') || SUBSTACK_PUBLICATION_URL,
          feedUrl: SUBSTACK_FEED_URL,
          authorName: SUBSTACK_AUTHOR_NAME,
          authorProfileUrl: SUBSTACK_AUTHOR_PROFILE_URL,
        },
        posts,
      }),
      {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
          'Cache-Control': 'public, max-age=600, stale-while-revalidate=1800',
        },
        status: 200,
      }
    )
  } catch (error) {
    console.error('[substack-feed] Error:', error)
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : 'Failed to load Substack feed',
        source: {
          title: '☭/Acc\'s Substack',
          url: SUBSTACK_PUBLICATION_URL,
          feedUrl: SUBSTACK_FEED_URL,
          authorName: SUBSTACK_AUTHOR_NAME,
          authorProfileUrl: SUBSTACK_AUTHOR_PROFILE_URL,
        },
        posts: [],
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )
  }
})
