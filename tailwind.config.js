/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.html'],
  theme: {
    extend: {
      fontFamily: {
        serif: ['Fraunces', 'Noto Serif Devanagari', 'serif'],
        sans: ['Inter', 'Noto Sans Devanagari', 'ui-sans-serif', 'sans-serif'],
      },
      colors: {
        paper: '#FAF8F3',
        sand: '#F2EFE6',
        ink: '#22261F',
        mist: '#6E7266',
        hairline: '#E3DFD2',
        moss: '#2F5233',
      },
    },
  },
  // JS toggles these class names as raw strings (classList.add/remove), so the
  // content scanner won't always see them attached to an element in markup.
  safelist: ['hidden', 'flex', 'grid', 'is-open', 'is-selected', 'active', 'intro-hide'],
  plugins: [],
};
