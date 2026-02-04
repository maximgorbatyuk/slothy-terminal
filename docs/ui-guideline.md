# SlothyTerminal UI Guidelines

## Brand Identity

**Tagline:** "Take it slow, ship it fast."

**Visual Style:**
- Clean, modern, developer-focused
- Blue/cyan color scheme inspired by code editors
- Professional yet approachable

---

## Color Palette

### Dark Mode (Default)

| Token | Hex | RGB | Usage |
|-------|-----|-----|-------|
| `--bg-primary` | `#0F172A` | rgb(15, 23, 42) | Page background |
| `--bg-secondary` | `#1E293B` | rgb(30, 41, 59) | Cards, sections |
| `--bg-tertiary` | `#334155` | rgb(51, 65, 85) | Hover states, inputs |
| `--text-primary` | `#E2E8F0` | rgb(226, 232, 240) | Headings, body text |
| `--text-secondary` | `#94A3B8` | rgb(148, 163, 184) | Secondary text, labels |
| `--text-muted` | `#64748B` | rgb(100, 116, 139) | Placeholders, hints |
| `--accent-primary` | `#38BDF8` | rgb(56, 189, 248) | Buttons, links, highlights |
| `--accent-secondary` | `#22D3EE` | rgb(34, 211, 238) | Secondary accents |

### Light Mode

| Token | Hex | RGB | Usage |
|-------|-----|-----|-------|
| `--bg-primary` | `#F8FAFC` | rgb(248, 250, 252) | Page background |
| `--bg-secondary` | `#E2E8F0` | rgb(226, 232, 240) | Cards, sections |
| `--bg-tertiary` | `#CBD5E1` | rgb(203, 213, 225) | Hover states, inputs |
| `--text-primary` | `#0F172A` | rgb(15, 23, 42) | Headings, body text |
| `--text-secondary` | `#475569` | rgb(71, 85, 105) | Secondary text, labels |
| `--text-muted` | `#94A3B8` | rgb(148, 163, 184) | Placeholders, hints |
| `--accent-primary` | `#0EA5E9` | rgb(14, 165, 233) | Buttons, links, highlights |
| `--accent-secondary` | `#06B6D4` | rgb(6, 182, 212) | Secondary accents |

### Semantic Colors

| Purpose | Dark Mode | Light Mode |
|---------|-----------|------------|
| Success | `#4AC77D` | `#3DA866` |
| Warning | `#F97316` | `#EA580C` |
| Error | `#EF4444` | `#DC2626` |

---

## Typography

### Font Families

| Token | Font Stack | Usage |
|-------|------------|-------|
| `--font-display` | Fraunces, Georgia, serif | Headings, titles |
| `--font-body` | DM Sans, -apple-system, sans-serif | Body text, UI elements |
| `--font-mono` | JetBrains Mono, SF Mono, monospace | Code, terminal text |

### Font Sizes

| Element | Size | Weight | Letter Spacing |
|---------|------|--------|----------------|
| Hero title | clamp(2.5rem, 6vw, 4rem) | 700 | -0.03em |
| Section title | clamp(1.8rem, 4vw, 2.5rem) | 700 | -0.02em |
| Feature title | 1.25rem | 600 | -0.01em |
| Body text | 1rem (16px) | 400 | normal |
| Small text | 0.85rem - 0.95rem | 400-500 | normal |
| Code | 0.85rem | 400 | normal |

---

## Spacing

| Token | Value | Usage |
|-------|-------|-------|
| `--section-padding` | clamp(60px, 10vw, 100px) | Vertical section spacing |
| `--container-max` | 1200px | Max content width |
| `--border-radius` | 16px | Cards, large elements |
| `--border-radius-sm` | 8px | Buttons, small elements |

### Spacing Scale

| Size | Value |
|------|-------|
| xs | 4px |
| sm | 8px |
| md | 16px |
| lg | 24px |
| xl | 32px |
| 2xl | 48px |
| 3xl | 64px |

---

## Components

### Buttons

**Primary Button**
```css
background: var(--accent-primary);
color: #0F172A;
font-weight: 600;
padding: 14px 28px;
border-radius: 12px;
```
- Hover: Lighten to `#7DD3FC`, translateY(-2px)

**Secondary Button**
```css
background: transparent;
border: 2px solid var(--accent-primary);
color: var(--accent-primary);
padding: 14px 28px;
border-radius: 12px;
```
- Hover: Background `var(--bg-secondary)`

**Large Button**
```css
padding: 18px 36px;
font-size: 1.1rem;
```

### Cards

```css
background: var(--bg-primary);
border: var(--card-border);
border-radius: var(--border-radius);
padding: 32px;
```
- Hover: translateY(-4px), box-shadow, border-color change

### Feature Cards

- Icon container: 56x56px, `--bg-tertiary` background, 14px radius
- Icon color: `--accent-primary`
- Title: `--font-display`, 1.25rem, 600 weight
- Description: `--text-secondary`, 0.95rem

### Code Blocks

```css
background: var(--bg-tertiary);
border-radius: var(--border-radius-sm);
padding: 16px 20px;
font-family: var(--font-mono);
font-size: 0.85rem;
```

### Navigation

```css
position: fixed;
background: var(--bg-primary);
border-bottom: var(--card-border);
padding: 16px 24px;
```

---

## Borders & Shadows

| Token | Value |
|-------|-------|
| `--border-color` | rgba(148, 163, 184, 0.1) |
| `--card-border` | 1px solid rgba(148, 163, 184, 0.1) |
| `--card-shadow` | 0 4px 24px rgba(0, 0, 0, 0.4) |

---

## Transitions

| Token | Duration | Usage |
|-------|----------|-------|
| `--transition-fast` | 0.15s ease | Hover states, color changes |
| `--transition-medium` | 0.3s ease | Layout changes, modals |
| `--transition-slow` | 0.5s ease | Page transitions, backgrounds |

---

## Layout

### Page Structure

```
+-------------------------------------+
|  Nav: Logo | Links | Theme Toggle   |  <- fixed
+-------------------------------------+
|                                     |
|  HERO                               |
|  [App Icon]                         |
|  SlothyTerminal                     |
|  "Take it slow, ship it fast."      |
|  [Download] [GitHub]                |
|                                     |
+-------------------------------------+
|                                     |
|  FEATURES (6 cards, 3x2 grid)       |
|                                     |
+-------------------------------------+
|                                     |
|  SCREENSHOT CAROUSEL                |
|                                     |
+-------------------------------------+
|                                     |
|  INSTALL (2 cards)                  |
|  Direct Download | Build from Source|
|                                     |
+-------------------------------------+
|                                     |
|  Footer: Brand | Projects | GitHub  |
|                                     |
+-------------------------------------+
```

### Responsive Breakpoints

| Breakpoint | Width | Changes |
|------------|-------|---------|
| Mobile | < 480px | Single column, reduced padding |
| Tablet | < 768px | Hide nav links, stack buttons |
| Desktop | > 768px | Full layout |

---

## Accessibility

### Focus States
```css
outline: 2px solid var(--accent-primary);
outline-offset: 2px;
```

### Reduced Motion
```css
@media (prefers-reduced-motion: reduce) {
  animation-duration: 0.01ms !important;
  transition-duration: 0.01ms !important;
}
```

### Color Contrast (WCAG AA)

| Combination | Ratio | Status |
|-------------|-------|--------|
| `--text-primary` on `--bg-primary` | 13.5:1 | Pass |
| `--text-secondary` on `--bg-primary` | 7.2:1 | Pass |
| `--accent-primary` on `--bg-primary` | 8.9:1 | Pass |
| `--accent-primary` (button text) on button | 7.1:1 | Pass |

### Selection
```css
::selection {
  background: var(--accent-primary);
  color: #fff;
}
```

---

## Animation

### Fade In Up (Page Load)
```css
@keyframes fadeInUp {
  from {
    opacity: 0;
    transform: translateY(20px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
```
- Duration: 0.6s
- Staggered delays: 0.05s - 0.35s

### Float (Hero Icon)
```css
@keyframes float {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-10px); }
}
```
- Duration: 6s infinite

### Cursor Blink
```css
@keyframes blink {
  0%, 50% { opacity: 1; }
  51%, 100% { opacity: 0; }
}
```
- Duration: 1s step-end infinite

---

## Assets

| Asset | Location | Format |
|-------|----------|--------|
| App Icon | `assets/SlothyTerminalIcon.jpg` | JPEG |
| Screenshots | `assets/*.png` | PNG |
| Favicon | `assets/SlothyTerminalIcon.jpg` | JPEG |

### Screenshot Naming

- `main_window.png` - Main window with tabs
- `claude.png` - Claude CLI session
- `opencode.png` - OpenCode session
- `open_new_tab.png` - New tab dialog
- `select_working_folder.png` - Folder selector

---

## CSS Custom Properties Reference

```css
:root {
  /* Colors */
  --bg-primary: #0F172A;
  --bg-secondary: #1E293B;
  --bg-tertiary: #334155;
  --text-primary: #E2E8F0;
  --text-secondary: #94A3B8;
  --text-muted: #64748B;
  --accent-primary: #38BDF8;
  --accent-secondary: #22D3EE;
  --border-color: rgba(148, 163, 184, 0.1);
  --card-shadow: 0 4px 24px rgba(0, 0, 0, 0.4);
  --card-border: 1px solid rgba(148, 163, 184, 0.1);

  /* Typography */
  --font-display: 'Fraunces', Georgia, serif;
  --font-body: 'DM Sans', -apple-system, BlinkMacSystemFont, sans-serif;
  --font-mono: 'JetBrains Mono', 'SF Mono', monospace;

  /* Spacing */
  --section-padding: clamp(60px, 10vw, 100px);
  --container-max: 1200px;
  --border-radius: 16px;
  --border-radius-sm: 8px;

  /* Transitions */
  --transition-fast: 0.15s ease;
  --transition-medium: 0.3s ease;
  --transition-slow: 0.5s ease;
}
```
