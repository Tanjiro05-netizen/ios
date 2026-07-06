import React, { useState, useEffect } from 'react';
import { StatusBar } from 'expo-status-bar';
import { NavigationContainer, createNavigationContainerRef } from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { Ionicons } from '@expo/vector-icons';
import { View, Text, ActivityIndicator, StyleSheet } from 'react-native';
import Toast from 'react-native-toast-message';

import { AuthProvider, useAuth } from './src/hooks/useAuth';
import { usePushNotifications } from './src/hooks/usePushNotifications';
import { COLORS, FONTS } from './src/constants';
import { RootStackParamList, MainTabParamList } from './src/types';
import { toastConfig } from './src/components/ToastConfig';
import { haptics } from './src/lib/haptics';
import { api } from './src/lib/api';
import ErrorBoundary from './src/components/ErrorBoundary';

import LoginScreen from './src/screens/LoginScreen';
import SignUpScreen from './src/screens/SignUpScreen';
import SettingsScreen from './src/screens/SettingsScreen';
import LibraryScreen from './src/screens/LibraryScreen';
import BookReaderScreen from './src/screens/BookReaderScreen';
import AudiobooksScreen from './src/screens/AudiobooksScreen';
import ForumScreen from './src/screens/ForumScreen';
import NotificationsScreen from './src/screens/NotificationsScreen';
import ProfileScreen from './src/screens/ProfileScreen';
import UserProfileScreen from './src/screens/UserProfileScreen';
import ThreadDetailScreen from './src/screens/ThreadDetailScreen';
import CreateThreadScreen from './src/screens/CreateThreadScreen';
import ChangePasswordScreen from './src/screens/ChangePasswordScreen';
import EmailPreferencesScreen from './src/screens/EmailPreferencesScreen';
import LegalScreen from './src/screens/LegalScreen';

export const navigationRef = createNavigationContainerRef<RootStackParamList>();

const Tab = createBottomTabNavigator<MainTabParamList>();
const Stack = createNativeStackNavigator<RootStackParamList>();

function NotificationBadge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <View style={badgeStyles.badge}>
      <Text style={badgeStyles.badgeText}>{count > 99 ? '99+' : count}</Text>
    </View>
  );
}

const badgeStyles = StyleSheet.create({
  badge: {
    position: 'absolute',
    top: -4,
    right: -8,
    minWidth: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: COLORS.primary,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 3,
  },
  badgeText: {
    color: '#fff',
    fontSize: 9,
    fontWeight: '700',
  },
});

function MainTabs() {
  const { user } = useAuth();
  const [unreadCount, setUnreadCount] = useState(0);

  useEffect(() => {
    if (!user) return;
    api.getUnreadCount(user.id).then(setUnreadCount);
  }, [user]);

  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarStyle: {
          backgroundColor: '#0e0e0e',
          borderTopColor: 'rgba(255,255,255,0.05)',
          borderTopWidth: 1,
          paddingBottom: 8,
          paddingTop: 8,
          height: 88,
        },
        tabBarActiveTintColor: COLORS.primary,
        tabBarInactiveTintColor: 'rgba(229, 226, 225, 0.4)',
        tabBarLabelStyle: {
          fontFamily: FONTS.family.mono,
          fontSize: 9,
          fontWeight: '500',
          textTransform: 'uppercase',
          letterSpacing: 1,
        },
        tabBarIcon: ({ focused, color }) => {
          let iconName: keyof typeof Ionicons.glyphMap;

          switch (route.name) {
            case 'Library':
              iconName = focused ? 'library' : 'library-outline';
              break;
            case 'Audiobooks':
              iconName = focused ? 'headset' : 'headset-outline';
              break;
            case 'Forum':
              iconName = focused ? 'chatbubbles' : 'chatbubbles-outline';
              break;
            case 'Notifications':
              iconName = focused ? 'notifications' : 'notifications-outline';
              break;
            case 'Profile':
              iconName = focused ? 'person' : 'person-outline';
              break;
            default:
              iconName = 'help-outline';
          }

          if (route.name === 'Notifications') {
            return (
              <View>
                <Ionicons name={iconName} size={24} color={color} />
                <NotificationBadge count={unreadCount} />
              </View>
            );
          }

          return <Ionicons name={iconName} size={24} color={color} />;
        },
      })}
      screenListeners={{
        tabPress: () => {
          haptics.selection();
        },
        state: () => {
          // Refresh unread count on any tab change
          if (user) {
            api.getUnreadCount(user.id).then(setUnreadCount);
          }
        },
      }}
    >
      <Tab.Screen name="Library" component={LibraryScreen} />
      <Tab.Screen name="Audiobooks" component={AudiobooksScreen} />
      <Tab.Screen name="Forum" component={ForumScreen} />
      <Tab.Screen name="Notifications" component={NotificationsScreen} />
      <Tab.Screen name="Profile" component={ProfileScreen} />
    </Tab.Navigator>
  );
}

function AppNavigator() {
  const { user, loading, isGuest } = useAuth();

  usePushNotifications(user);

  if (loading) {
    return (
      <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: COLORS.background }}>
        <ActivityIndicator size="large" color={COLORS.primary} />
      </View>
    );
  }

  const isAuthenticated = user || isGuest;

  return (
    <Stack.Navigator
      screenOptions={{
        headerStyle: {
          backgroundColor: COLORS.background,
        },
        headerShadowVisible: false,
        headerTintColor: COLORS.text,
        headerTitleStyle: {
          fontWeight: '600',
          fontSize: 17,
        },
        headerBackButtonDisplayMode: 'minimal',
      }}
    >
      {isAuthenticated ? (
        <>
          <Stack.Screen
            name="Main"
            component={MainTabs}
            options={{ headerShown: false }}
          />
          <Stack.Screen
            name="Settings"
            component={SettingsScreen}
            options={{ title: 'Settings' }}
          />
          <Stack.Screen
            name="BookReader"
            component={BookReaderScreen}
            options={{ headerShown: false }}
          />
          <Stack.Screen
            name="UserProfile"
            component={UserProfileScreen}
            options={{ headerShown: false }}
          />
          <Stack.Screen
            name="ThreadDetail"
            component={ThreadDetailScreen}
            options={{ headerShown: false }}
          />
          <Stack.Screen
            name="CreateThread"
            component={CreateThreadScreen}
            options={{ headerShown: false }}
          />
          <Stack.Screen
            name="ChangePassword"
            component={ChangePasswordScreen}
            options={{ title: 'Change Password' }}
          />
          <Stack.Screen
            name="EmailPreferences"
            component={EmailPreferencesScreen}
            options={{ title: 'Email Preferences' }}
          />
          <Stack.Screen
            name="Legal"
            component={LegalScreen}
            options={({ route }) => ({
              title: route.params.type === 'terms' ? 'Terms of Service'
                : route.params.type === 'privacy' ? 'Privacy Policy'
                : 'Community Guidelines',
            })}
          />
        </>
      ) : (
        <>
          <Stack.Screen
            name="Login"
            component={LoginScreen}
            options={{ headerShown: false }}
          />
          <Stack.Screen
            name="SignUp"
            component={SignUpScreen}
            options={{ title: 'Create Account' }}
          />
          <Stack.Screen
            name="Legal"
            component={LegalScreen}
            options={({ route }) => ({
              title: route.params.type === 'terms' ? 'Terms of Service'
                : route.params.type === 'privacy' ? 'Privacy Policy'
                : 'Community Guidelines',
            })}
          />
        </>
      )}
    </Stack.Navigator>
  );
}

export default function App() {
  return (
    <ErrorBoundary>
      <AuthProvider>
          <NavigationContainer ref={navigationRef}>
            <StatusBar style="light" />
            <AppNavigator />
            <Toast config={toastConfig} />
          </NavigationContainer>
        </AuthProvider>
    </ErrorBoundary>
  );
}
