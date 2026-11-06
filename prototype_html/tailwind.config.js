/** Tailwind config — SIGH-CBG / CLINIQUE BAGUIDI « L'AS DE CŒUR »
 *  Charte BAGUIDI (Instructions.txt) : Rouge Cœur #D32F2F (actions, accents),
 *  Bleu Santé #1565C0 (titres, badges), Noir Anthracite #212121 (texte, barres
 *  sombres), fonds blanc/gris médical #F8F9FA. La sémantique d'état reste
 *  vert (validé) / orange (alerte) / rouge (rupture, erreur).
 *  NUANCE DOCUMENTÉE : le rouge d'ACTION (coeur-500 #D32F2F, boutons pleins)
 *  et le rouge d'ERREUR (danger-500 #ef4444, badges et alertes sur fond clair)
 *  restent distinguables — teinte plus profonde d'un côté, vive de l'autre.
 *  Build : npm run css  (voir package.json)
 */
module.exports = {
  content: [
    './index.html',
    './pages/**/*.html',
    './build/safelist.html', // classes produites dynamiquement en JS (cf. build/gen-safelist.js)
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'Segoe UI', 'system-ui', 'sans-serif'],
        /* Titres — Montserrat (vendorée localement, repli sans-serif). */
        heading: ['Montserrat', 'Inter', 'Segoe UI', 'system-ui', 'sans-serif'],
        /* EXCLUSIVEMENT pour le slogan — cursive (Dancing Script vendorée). */
        slogan: ['Dancing Script', 'Segoe Script', 'cursive'],
        mono: ['Consolas', 'ui-monospace', 'monospace'],
      },
      colors: {
        /* Rouge Cœur — couleur principale / actions (base 500 = #D32F2F). */
        coeur: {
          50: '#fdecec', 100: '#fbd8d8', 200: '#f6b1b1', 300: '#ee8383',
          400: '#e35555', 500: '#D32F2F', 600: '#b62222', 700: '#971c1c',
          800: '#7d1a1a', 900: '#671717', 950: '#3f0d0d',
        },
        /* Bleu Santé — couleur secondaire / titres, badges (base 600 = #1565C0). */
        sante: {
          50: '#eef4fc', 100: '#d9e7f8', 200: '#b6d0f1', 300: '#8ab3e8',
          400: '#5590da', 500: '#2f74cc', 600: '#1565C0', 700: '#1253a0',
          800: '#124684', 900: '#123a6b', 950: '#0c2647',
        },
        /* Noir Anthracite — textes et barres sombres. */
        anthracite: { DEFAULT: '#212121', 800: '#2b2b2b', 900: '#212121', 950: '#1a1a1a' },
        /* `navy` est REMAPPÉ sur la charte BAGUIDI : les composants du design
           system (titres, badges, onglets, liens) qui composaient en bleu
           institutionnel composent désormais en BLEU SANTÉ, et les nuances
           les plus sombres (900/950 — topbar, ruban, barres) tirent vers le
           NOIR ANTHRACITE. Les classes ne changent pas : la palette, si. */
        navy: {
          50: '#eef4fc', 100: '#d9e7f8', 200: '#b6d0f1', 300: '#8ab3e8',
          400: '#5590da', 500: '#2f74cc', 600: '#1565C0', 700: '#1253a0',
          800: '#124684', 900: '#123a6b', 950: '#212121',
        },
        success: {
          50: '#eefbf4', 100: '#d6f5e3', 200: '#b0e9cc', 300: '#7bd7ae',
          400: '#45bd8b', 500: '#22a170', 600: '#15825a', 700: '#12684a',
          800: '#12523c', 900: '#104433',
        },
        warning: {
          50: '#fff8eb', 100: '#ffedc6', 200: '#ffd888', 300: '#ffbe4a',
          400: '#ffa620', 500: '#f98307', 600: '#dd5f02', 700: '#b74106',
          800: '#94320c', 900: '#7a2a0d',
        },
        danger: {
          50: '#fef2f2', 100: '#fee2e2', 200: '#fecaca', 300: '#fca5a5',
          400: '#f87171', 500: '#ef4444', 600: '#dc2626', 700: '#b91c1c',
          800: '#991b1b', 900: '#7f1d1d',
        },
        info: {
          50: '#eff8ff', 100: '#dbeefe', 200: '#bfe2fe', 300: '#92d0fd',
          400: '#61b6fa', 500: '#3b98f6', 600: '#257aeb', 700: '#1d63d8',
          800: '#1e51af', 900: '#1e468a',
        },
      },
      boxShadow: {
        card: '0 1px 2px 0 rgb(11 30 61 / 0.05), 0 1px 3px 0 rgb(11 30 61 / 0.06)',
        raise: '0 4px 12px -2px rgb(11 30 61 / 0.10), 0 2px 6px -2px rgb(11 30 61 / 0.06)',
        pop: '0 12px 32px -8px rgb(11 30 61 / 0.22)',
      },
      keyframes: {
        'fade-in': { '0%': { opacity: '0' }, '100%': { opacity: '1' } },
        'slide-in': { '0%': { transform: 'translateX(100%)' }, '100%': { transform: 'translateX(0)' } },
        'pop-in': { '0%': { opacity: '0', transform: 'scale(.97) translateY(4px)' }, '100%': { opacity: '1', transform: 'scale(1) translateY(0)' } },
      },
      animation: {
        'fade-in': 'fade-in .15s ease-out',
        'slide-in': 'slide-in .2s cubic-bezier(.32,.72,0,1)',
        'pop-in': 'pop-in .16s ease-out',
      },
    },
  },
  plugins: [],
}
