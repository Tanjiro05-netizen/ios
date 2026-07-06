-- Add is_official column to digital_library_books table
-- This enables filtering between official library books and community uploads
ALTER TABLE digital_library_books
  ADD COLUMN IF NOT EXISTS is_official BOOLEAN NOT NULL DEFAULT true;

-- Index for efficient filtering
CREATE INDEX IF NOT EXISTS idx_digital_library_books_is_official
  ON digital_library_books (is_official);
