/** shadcn zinc tokens on Tailwind. 12px is the working size, 11px the small one. */
module.exports = {
  content: ['./index.html', './app.js'],
  theme: { extend: {
    colors: {
      border: 'hsl(var(--border))', foreground: 'hsl(var(--foreground))',
      muted: { DEFAULT: 'hsl(var(--muted))', foreground: 'hsl(var(--muted-foreground))' },
      accent: { DEFAULT: 'hsl(var(--accent))', foreground: 'hsl(var(--accent-foreground))' },
      primary: { DEFAULT: 'hsl(var(--primary))', foreground: 'hsl(var(--primary-foreground))' },
      ring: 'hsl(var(--ring))',
    },
    fontFamily: { sans: ['Inter', '-apple-system', 'BlinkMacSystemFont', 'SF Pro Text', 'system-ui', 'sans-serif'], mono: ['SF Mono', 'ui-monospace', 'Menlo', 'monospace'] },
    fontSize: { xs: ['11px', '14px'], sm: ['12px', '16px'] },
    borderRadius: { sm: '4px', md: '6px', lg: '8px' },
  } },
};
