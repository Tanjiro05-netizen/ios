import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRoute, RouteProp } from '@react-navigation/native';

import { COLORS, SPACING, FONTS } from '../constants';
import { RootStackParamList } from '../types';

type LegalRouteProp = RouteProp<RootStackParamList, 'Legal'>;

const LEGAL_CONTENT: Record<string, { title: string; lastUpdated: string; sections: { heading: string; body: string }[] }> = {
  terms: {
    title: 'Terms of Service',
    lastUpdated: 'April 2026',
    sections: [
      {
        heading: '1. Acceptance of Terms',
        body: 'By accessing or using the Marxist Library application ("the App"), you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the App.',
      },
      {
        heading: '2. Use of the Service',
        body: 'The App provides access to a digital library of texts, audiobooks, and community discussion forums. You agree to use the service only for lawful purposes and in accordance with these terms. You may not use the App in any way that could damage, disable, or impair the service.',
      },
      {
        heading: '3. User Accounts',
        body: 'To access certain features, you may need to create an account. You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account. You must provide accurate and complete information when creating your account.',
      },
      {
        heading: '4. User Content',
        body: 'You retain ownership of any content you post to the App, including forum posts and comments. By posting content, you grant us a non-exclusive, worldwide license to display, distribute, and store your content within the App. You are solely responsible for the content you post.',
      },
      {
        heading: '5. Prohibited Conduct',
        body: 'You may not: post content that is illegal, threatening, abusive, or harassing; impersonate any person or entity; upload malicious software or content; attempt to gain unauthorized access to other accounts or systems; use the App for commercial solicitation without permission.',
      },
      {
        heading: '6. Intellectual Property',
        body: 'The texts and audiobooks available in the library are provided for educational and scholarly purposes. Many works are in the public domain. Where applicable, proper attribution is given to authors and translators.',
      },
      {
        heading: '7. Termination',
        body: 'We reserve the right to suspend or terminate your account at our discretion if you violate these terms. You may delete your account at any time through the App settings.',
      },
      {
        heading: '8. Disclaimer',
        body: 'The App is provided "as is" without warranties of any kind, either express or implied. We do not guarantee that the service will be uninterrupted or error-free.',
      },
      {
        heading: '9. Changes to Terms',
        body: 'We may update these terms from time to time. Continued use of the App after changes constitutes acceptance of the updated terms.',
      },
    ],
  },
  privacy: {
    title: 'Privacy Policy',
    lastUpdated: 'April 2026',
    sections: [
      {
        heading: '1. Information We Collect',
        body: 'We collect minimal information needed to provide the service:\n\n• Account information: email address, username, and optional profile details you choose to provide.\n• Usage data: reading history and preferences stored locally on your device.\n• Push notification tokens: if you opt in to notifications.',
      },
      {
        heading: '2. How We Use Your Information',
        body: 'We use your information to:\n\n• Provide and maintain the App.\n• Send notifications you have opted into.\n• Improve the service based on aggregate, anonymised usage patterns.\n• Communicate important service updates.',
      },
      {
        heading: '3. Data Storage',
        body: 'Account data is stored securely using Supabase, hosted on infrastructure with industry-standard security. Reading progress and preferences are stored locally on your device.',
      },
      {
        heading: '4. Data Sharing',
        body: 'We do not sell your personal information. We do not share your data with third parties except as necessary to provide the service (e.g., hosting providers) or as required by law.',
      },
      {
        heading: '5. Your Rights',
        body: 'You have the right to:\n\n• Access your personal data.\n• Request correction of inaccurate data.\n• Request deletion of your account and associated data.\n• Export your data.\n• Opt out of non-essential communications.',
      },
      {
        heading: '6. Cookies and Local Storage',
        body: 'The App uses local device storage (AsyncStorage) to persist your preferences, reading progress, and session information. No third-party tracking cookies are used.',
      },
      {
        heading: '7. Children\'s Privacy',
        body: 'The App is not directed at children under 13. We do not knowingly collect personal information from children under 13.',
      },
      {
        heading: '8. Changes to This Policy',
        body: 'We may update this privacy policy from time to time. We will notify you of significant changes through the App.',
      },
      {
        heading: '9. Contact',
        body: 'If you have questions about this privacy policy, please reach out through the feedback channels in the App.',
      },
    ],
  },
  guidelines: {
    title: 'Community Guidelines',
    lastUpdated: 'April 2026',
    sections: [
      {
        heading: 'Our Mission',
        body: 'The Marxist Library community is a space for good-faith discussion, study, and debate around Marxist theory, history, and practice. These guidelines exist to keep the community productive and welcoming.',
      },
      {
        heading: '1. Respectful Discourse',
        body: 'Engage with ideas critically but respectfully. Personal attacks, insults, and harassment are not tolerated. Disagree with arguments, not people.',
      },
      {
        heading: '2. Good Faith Participation',
        body: 'Contribute constructively to discussions. Avoid trolling, derailing threads, and posting low-effort or spam content. Cite sources when making empirical claims.',
      },
      {
        heading: '3. Inclusive Environment',
        body: 'Discrimination based on race, gender, sexuality, religion, nationality, disability, or any other identity is strictly prohibited. The community is open to all who engage in good faith.',
      },
      {
        heading: '4. No Incitement',
        body: 'Do not post content that incites or glorifies violence against any group or individual. Theoretical and historical discussion of revolutionary movements should remain analytical and scholarly.',
      },
      {
        heading: '5. Stay On Topic',
        body: 'Use the appropriate boards for your discussions. Each board has a description of its intended purpose. Off-topic posts may be moved or removed by moderators.',
      },
      {
        heading: '6. Content Standards',
        body: 'Do not post illegal content, doxxing, or personally identifiable information of others. Copyrighted material should only be shared within fair use guidelines.',
      },
      {
        heading: '7. Moderation',
        body: 'Moderators may remove content, issue warnings, or suspend accounts that violate these guidelines. If you believe an action was taken in error, you may appeal through the appropriate channels.',
      },
      {
        heading: '8. Reporting',
        body: 'If you see content that violates these guidelines, please report it using the options menu on the relevant post. Reports are reviewed by the moderation team.',
      },
    ],
  },
};

export default function LegalScreen() {
  const route = useRoute<LegalRouteProp>();
  const { type } = route.params;

  const content = LEGAL_CONTENT[type];

  if (!content) {
    return (
      <SafeAreaView style={styles.container} edges={['bottom']}>
        <View style={styles.errorContainer}>
          <Text style={styles.errorText}>Content not found.</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      <ScrollView style={styles.scrollView} contentContainerStyle={styles.scrollContent}>
        <Text style={styles.title}>{content.title}</Text>
        <Text style={styles.lastUpdated}>Last updated: {content.lastUpdated}</Text>

        {content.sections.map((section, index) => (
          <View key={index} style={styles.sectionBlock}>
            <Text style={styles.sectionHeading}>{section.heading}</Text>
            <Text style={styles.sectionBody}>{section.body}</Text>
          </View>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  errorText: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.md,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: SPACING.xl,
    paddingTop: SPACING.xl,
    paddingBottom: SPACING.xxxl,
  },
  title: {
    fontFamily: FONTS.family.display,
    fontSize: 28,
    fontWeight: '700',
    color: COLORS.text,
    marginBottom: SPACING.xs,
  },
  lastUpdated: {
    fontFamily: FONTS.family.mono,
    fontSize: FONTS.sizes.xs,
    color: COLORS.textTertiary,
    letterSpacing: 0.5,
    marginBottom: SPACING.xl,
  },
  sectionBlock: {
    marginBottom: SPACING.xl,
  },
  sectionHeading: {
    fontFamily: FONTS.family.display,
    fontSize: FONTS.sizes.lg,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: SPACING.sm,
  },
  sectionBody: {
    fontFamily: FONTS.family.body,
    fontSize: FONTS.sizes.md,
    color: COLORS.textSecondary,
    lineHeight: 24,
  },
});
