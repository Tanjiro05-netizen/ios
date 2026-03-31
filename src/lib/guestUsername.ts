// Random username generator for guest users
// Creates names like "BraveLion42", "SwiftFalcon789", etc.

const adjectives = [
  'Brave', 'Swift', 'Clever', 'Bold', 'Wise',
  'Fierce', 'Noble', 'Proud', 'Wild', 'Free',
  'Quick', 'Bright', 'Strong', 'Keen', 'Sharp',
  'Lucky', 'Calm', 'Cool', 'Warm', 'Kind',
  'Dark', 'Light', 'Red', 'Blue', 'Golden',
  'Silent', 'Loud', 'Humble', 'Mighty', 'Tiny',
  'Ancient', 'Young', 'Old', 'New', 'Eternal',
  'Cosmic', 'Solar', 'Lunar', 'Stellar', 'Frost',
];

const animals = [
  // Land animals
  'Lion', 'Tiger', 'Bear', 'Wolf', 'Fox',
  'Eagle', 'Hawk', 'Falcon', 'Owl', 'Raven',
  'Panther', 'Leopard', 'Jaguar', 'Cheetah', 'Lynx',
  'Deer', 'Elk', 'Moose', 'Bison', 'Buffalo',
  'Horse', 'Stallion', 'Mustang', 'Zebra', 'Donkey',
  // Sea creatures
  'Shark', 'Whale', 'Dolphin', 'Orca', 'Seal',
  'Octopus', 'Squid', 'Crab', 'Lobster', 'Turtle',
  // Birds
  'Sparrow', 'Robin', 'Crane', 'Heron', 'Swan',
  'Penguin', 'Pelican', 'Parrot', 'Peacock', 'Phoenix',
  // Mythical/cool
  'Dragon', 'Griffin', 'Sphinx', 'Hydra', 'Kraken',
  // More common
  'Rabbit', 'Badger', 'Otter', 'Beaver', 'Raccoon',
  'Panda', 'Koala', 'Sloth', 'Gorilla', 'Chimp',
];

/**
 * Generates a random username like "BraveLion42"
 */
export function generateGuestUsername(): string {
  const adjective = adjectives[Math.floor(Math.random() * adjectives.length)];
  const animal = animals[Math.floor(Math.random() * animals.length)];
  const number = Math.floor(Math.random() * 1000); // 0-999

  return `${adjective}${animal}${number}`;
}

/**
 * Generates a unique guest ID
 */
export function generateGuestId(): string {
  return `guest_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}
