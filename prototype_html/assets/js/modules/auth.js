/* =============================================================================
 * Écrans d'accès — connexion, récupération, double facteur, verrouillage, erreurs
 * -----------------------------------------------------------------------------
 * CDCT §12.2 : authentification individuelle obligatoire (aucun compte partagé),
 * politique de mot de passe, verrouillage après échecs successifs, MFA pour les
 * profils à privilèges élevés, déconnexion automatique sur poste partagé.
 * ========================================================================== */
(function (global) {
  'use strict';
  var C = global.SIGH.core, U = global.SIGH.ui, S = global.SIGH.store, N = global.SIGH.nav, K = global.SIGH.kit;
  var el = C.el, B = C.BRAND;

  function base() { return document.documentElement.getAttribute('data-root') || ''; }
  function url(id) { return id === 'index' ? base() + 'index.html' : base() + 'pages/' + id + '.html'; }

  /* ==========================================================================
   * Gabarit commun des écrans d'accès — PANNEAU FLOTTANT (03/09/2026)
   * --------------------------------------------------------------------------
   * Décor arrêté sur les maquettes remises par la Direction (design/) : une
   * page claire aux grandes formes bleues adoucies, et au centre un PANNEAU
   * ARRONDI qui flotte — moitié gauche en dégradé Bleu Santé portant toute
   * l'identité BAGUIDI (en-tête, périmètre, spécialités, slogan), moitié
   * droite en carte blanche portant le formulaire. La double ligne fine rouge
   * et bleue de l'en-tête officiel court au sommet du panneau.
   * ======================================================================== */
  function shell(options) {
    var o = options || {};

    /* --- La page : fond clair, formes bleues douces, halo rouge discret --- */
    var wrap = el('div.relative.flex.min-h-screen.items-center.justify-center.overflow-hidden.bg-gradient-to-br.from-slate-100.via-sante-50.to-sante-100.p-4.sm\\:p-8');
    wrap.appendChild(el('div.pointer-events-none.absolute.-left-40.-top-40.h-\\[34rem\\].w-\\[34rem\\].rounded-full.bg-sante-200\\/70.blur-3xl'));
    wrap.appendChild(el('div.pointer-events-none.absolute.-bottom-48.-right-32.h-\\[38rem\\].w-\\[38rem\\].rounded-full.bg-sante-300\\/50.blur-3xl'));
    wrap.appendChild(el('div.pointer-events-none.absolute.left-1\\/3.top-1\\/4.h-72.w-72.rounded-full.bg-coeur-100\\/60.blur-3xl'));
    wrap.appendChild(el('div.pointer-events-none.absolute.-right-10.top-8.h-40.w-40.rotate-12.rounded-\\[3rem\\].bg-sante-200\\/60.blur-xl'));
    wrap.appendChild(el('div.pointer-events-none.absolute.bottom-10.left-6.h-32.w-64.-rotate-6.rounded-full.bg-sante-200\\/50.blur-xl'));

    /* --- Le panneau flottant ------------------------------------------------ */
    var panneau = el('div.relative.z-10.flex.w-full.max-w-6xl.flex-col.overflow-hidden.rounded-3xl.bg-white.shadow-pop');
    var filet = el('div');
    filet.appendChild(el('div.h-\\[3px\\].bg-coeur-500'));
    filet.appendChild(el('div.h-\\[3px\\].bg-sante-600'));
    panneau.appendChild(filet);

    var colonnes = el('div.flex.min-h-\\[36rem\\].flex-1');

    /* --- Moitié gauche : l'identité BAGUIDI sur dégradé Bleu Santé --------- */
    var aside = el('aside.relative.hidden.flex-col.justify-between.overflow-hidden.bg-gradient-to-br.from-sante-600.via-sante-700.to-sante-900.p-10.lg\\:flex.lg\\:w-\\[55\\%\\]');
    /* Les formes douces des maquettes : deux disques translucides et le
       battement de cœur en filigrane. */
    aside.appendChild(el('div.pointer-events-none.absolute.-left-24.-top-24.h-80.w-80.rounded-full.bg-white\\/10'));
    aside.appendChild(el('div.pointer-events-none.absolute.-bottom-28.-left-10.h-72.w-72.rounded-full.bg-sante-400\\/30.blur-xl'));
    aside.appendChild(el('div.pointer-events-none.absolute.-right-16.top-1\\/3.h-56.w-56.rounded-full.bg-white\\/5'));
    aside.appendChild(el('div.pointer-events-none.absolute.-bottom-8.right-4.text-white\\/10', null,
      C.icon('heart-pulse', 'h-64 w-64')));

    /* L'EN-TÊTE BAGUIDI — dénomination, sous-titre, ville. */
    var top = el('div.relative');
    var marque = el('div.flex.items-center.gap-4');
    marque.appendChild(el('span.grid.h-16.w-16.shrink-0.place-items-center.overflow-hidden.rounded-full.bg-white.shadow-raise', null,
      el('img.h-14.w-14.rounded-full.object-contain', {
        src: base() + B.logo, alt: B.sigle,
        onerror: function () { this.replaceWith(el('span.text-base.font-bold.text-navy-900', { text: B.sigle })); },
      })));
    marque.appendChild(el('div', null, [
      el('p.font-heading.text-lg.font-bold.leading-tight.text-white', { text: B.nom }),
      el('p.text-\\[11px\\].font-semibold.uppercase.tracking-wide.text-sante-200', { text: B.sousTitre }),
      el('p.text-xs.text-sante-200\\/80', { text: 'Parakou — République du Bénin' }),
    ]));
    top.appendChild(marque);
    aside.appendChild(top);

    var mid = el('div.relative.max-w-lg');
    mid.appendChild(el('h1.font-heading.text-3xl.font-semibold.leading-tight.tracking-tight.text-white', {
      text: 'Système Intégré de Gestion Hospitalière',
    }));
    mid.appendChild(el('p.mt-3.text-sm.leading-relaxed.text-sante-100', {
      text: 'Gestion des stocks et inventaire de la pharmacie, achats et expressions de besoins, '
        + 'ressources humaines, paie et primes, comptabilité SYSCOHADA, pilotage et tableaux de bord.',
    }));

    /* Les spécialités de la clinique, en pastilles — référentiel de
       présentation d'Instructions.txt. */
    var chips = el('div.mt-6.flex.max-w-md.flex-wrap.gap-1\\.5');
    (B.specialites || []).slice(0, 7).forEach(function (s) {
      chips.appendChild(el('span.rounded-full.border.border-white\\/25.bg-white\\/10.px-2\\.5.py-1.text-\\[11px\\].text-white', { text: s }));
    });
    if ((B.specialites || []).length > 7) {
      chips.appendChild(el('span.rounded-full.bg-white.px-2\\.5.py-1.text-\\[11px\\].font-semibold.text-sante-700', {
        text: '+ ' + (B.specialites.length - 7) + ' spécialités',
      }));
    }
    mid.appendChild(chips);
    aside.appendChild(mid);

    var basAside = el('div.relative');
    basAside.appendChild(el('p.font-slogan.text-2xl.text-white', { text: B.slogan }));
    basAside.appendChild(el('p.mt-2.text-xs.text-sante-200\\/80', {
      text: B.nom + ' — IFU ' + B.ifu + (B.rccm ? ' — RCCM ' + B.rccm : ' — RCCM : à compléter par la Direction'),
    }));
    aside.appendChild(basAside);
    colonnes.appendChild(aside);

    /* --- Moitié droite : la carte blanche du formulaire -------------------- */
    var main = el('main.flex.w-full.items-center.justify-center.bg-white.p-6.sm\\:p-10.lg\\:w-\\[45\\%\\]');
    var card = el('div.w-full.max-w-md');

    /* Sur petit écran, la moitié bleue disparaît : l'en-tête BAGUIDI se
       replie en tête de carte pour que l'identité reste visible. */
    var brandSm = el('div.mb-8.flex.items-center.gap-3.lg\\:hidden');
    brandSm.appendChild(el('span.grid.h-12.w-12.shrink-0.place-items-center.overflow-hidden.rounded-full.bg-white.ring-2.ring-sante-600', null,
      el('img.h-10.w-10.rounded-full.object-contain', {
        src: base() + B.logo, alt: B.sigle,
        onerror: function () { this.replaceWith(el('span.text-sm.font-bold.text-navy-900', { text: B.sigle })); },
      })));
    brandSm.appendChild(el('div', null, [
      el('p.font-heading.text-sm.font-bold.text-navy-900', { text: B.nom }),
      el('p.text-\\[10px\\].uppercase.tracking-wide.text-slate-500', { text: B.sousTitre }),
    ]));
    card.appendChild(brandSm);

    if (o.icon) {
      card.appendChild(el('span.mb-4.grid.h-12.w-12.place-items-center.rounded-xl.bg-sante-50.text-sante-700', null, C.icon(o.icon, 'h-6 w-6')));
    }
    card.appendChild(el('h2.font-heading.text-2xl.font-semibold.tracking-tight.text-navy-900', { text: o.titre }));
    if (o.sousTitre) card.appendChild(el('p.mt-1\\.5.text-sm.text-slate-500', { text: o.sousTitre }));
    var body = el('div.mt-6');
    C.append(body, o.body);
    card.appendChild(body);
    if (o.pied) card.appendChild(el('div.mt-6.text-center.text-sm.text-slate-500', null, o.pied));

    main.appendChild(card);
    colonnes.appendChild(main);
    panneau.appendChild(colonnes);
    wrap.appendChild(panneau);
    return wrap;
  }

  /* ==========================================================================
   * CONNEXION
   * ======================================================================== */
  global.SIGH.screen('index', {
    standalone: true,
    render: function (root) {
      /* ====================================================================
       * LES HUIT COMPTES DE TEST BAGUIDI — Instructions.txt, EXACTEMENT
       * (décision écrite de la Direction du 02/09/2026), plus le compte
       * d'administration système. Aucun autre compte ne s'invente.
       *
       * L'identifiant est l'adresse m-00X@baguidi-clinique.bj de la liste.
       * Le rôle ouvre les écrans ; la fonction et le secteur décident des
       * données. Médecin et infirmier EXISTENT (comptes actifs) même si
       * leurs modules cliniques sont fermés : ils gardent leur tableau de
       * bord — qui annonce le périmètre actuel — et l'expression de besoins.
       * ================================================================== */
      var comptes = [
        { role: 'direction', nom: 'GBAGUIDI Rafiou — Directeur Général',
          identifiant: 'm-001@baguidi-clinique.bj', fonction: 'direction', secteur: 'ADM' },
        { role: 'comptable', nom: 'SANOUSSI Adamon',
          identifiant: 'm-002@baguidi-clinique.bj', fonction: 'comptable', secteur: 'ADM' },
        { role: 'rh', nom: 'MABOUDOU Nawal',
          identifiant: 'm-003@baguidi-clinique.bj', fonction: 'rh', secteur: 'ADM' },
        { role: 'medecin', nom: 'IDOHOU Abraham',
          identifiant: 'm-004@baguidi-clinique.bj', fonction: 'medecin', secteur: 'MGE' },
        { role: 'infirmier', nom: 'AKONDE Octave',
          identifiant: 'm-005@baguidi-clinique.bj', fonction: 'infirmier', secteur: 'SUR' },
        { role: 'direction', nom: 'SOKOU Peace',
          identifiant: 'm-006@baguidi-clinique.bj', fonction: 'direction', secteur: 'ADM' },
        { role: 'comptable', nom: 'ZIME Nadège',
          identifiant: 'm-007@baguidi-clinique.bj', fonction: 'comptable', secteur: 'ADM' },
        { role: 'rh', nom: 'TOUNGOUH A. Zoulkifouli',
          identifiant: 'm-008@baguidi-clinique.bj', fonction: 'rh', secteur: 'ADM' },
        /* Le poste d'administrateur système EST l'accès complet — compte
           technique, pas un agent de l'effectif. */
        { role: 'admin', nom: 'Administrateur système',
          identifiant: 'admin@baguidi-clinique.bj', fonction: 'direction', secteur: 'ADM' },
      ];

      var form = el('form.space-y-4');
      var idField = el('input.input', { type: 'text', id: 'identifiant', autocomplete: 'username', placeholder: 'prenom.nom', required: true });
      var pwField = el('input.input.pr-10', { type: 'password', id: 'motdepasse', autocomplete: 'current-password', placeholder: '••••••••', required: true });

      form.appendChild(el('div', null, [
        el('label.label', { for: 'identifiant', text: 'Identifiant' }),
        idField,
      ]));

      var pwWrap = el('div.relative');
      pwWrap.appendChild(pwField);
      pwWrap.appendChild(el('button.absolute.right-2.top-1\\/2.-translate-y-1\\/2.rounded.p-1.text-slate-400.hover\\:text-slate-700', {
        type: 'button', 'aria-label': 'Afficher le mot de passe',
        onclick: function () {
          var vis = pwField.type === 'text';
          pwField.type = vis ? 'password' : 'text';
          C.clear(this); this.appendChild(C.icon(vis ? 'eye' : 'eye-off', 'h-4 w-4'));
          U.icons(this);
        },
      }, C.icon('eye', 'h-4 w-4')));
      form.appendChild(el('div', null, [
        el('div.flex.items-center.justify-between', null, [
          el('label.label.mb-0', { for: 'motdepasse', text: 'Mot de passe' }),
          el('a.text-xs.font-medium.text-navy-700.hover\\:underline', { href: url('auth-forgot'), text: 'Mot de passe oublié ?' }),
        ]),
        el('div.mt-1\\.5', null, pwWrap),
      ]));

      /* Sélection du profil — le prototype ne vérifie pas de mot de passe réel. */
      var sel = el('select.select');
      comptes.forEach(function (c) {
        /* Un libellé PROPRE par option (Bug 0 des Instructions) : le nom de
           compte porte parfois la fonction en suffixe pour distinguer deux
           sessions d'un même agent — la répéter après le libellé du rôle
           donnait « Rôle — Nom — Rôle ». On n'affiche que le nom nu. */
        var nomCourt = String(c.nom).split(' — ')[0];
        sel.appendChild(el('option', { value: c.role }, N.ROLES[c.role].label + ' — ' + nomCourt));
      });
      sel.addEventListener('change', function () {
        var c = comptes.filter(function (x) { return x.role === sel.value; })[0];
        if (c) { idField.value = c.identifiant; pwField.value = 'demonstration'; }
      });
      form.appendChild(el('div', null, [
        el('label.label', { text: 'Profil de connexion (démonstration)' }),
        sel,
        el('p.mt-1.text-xs.text-slate-400', { text: 'Le prototype ouvre la session avec le périmètre RBAC du profil choisi.' }),
      ]));

      form.appendChild(el('div.flex.items-center.justify-between', null, [
        el('label.flex.cursor-pointer.items-center.gap-2', null, [
          el('input.checkbox', { type: 'checkbox' }),
          el('span.text-sm.text-slate-600', { text: 'Se souvenir de ce poste' }),
        ]),
      ]));

      var erreur = el('div.hidden.items-start.gap-2.rounded-lg.border.border-danger-200.bg-danger-50.px-3.py-2');
      erreur.appendChild(el('span.shrink-0.text-danger-600', null, C.icon('alert-circle', 'h-4 w-4')));
      var erreurTexte = el('p.text-xs.text-danger-900');
      erreur.appendChild(erreurTexte);
      form.appendChild(erreur);

      var tentatives = 0;
      var submit = el('button.btn.btn-primary.btn-lg.w-full', { type: 'submit' }, [C.icon('log-in', 'h-4 w-4'), 'Se connecter']);
      form.appendChild(submit);

      form.addEventListener('submit', function (e) {
        e.preventDefault();
        if (!idField.value.trim() || !pwField.value) {
          tentatives++;
          erreur.className = 'flex items-start gap-2 rounded-lg border border-danger-200 bg-danger-50 px-3 py-2';
          erreurTexte.textContent = tentatives >= 3
            ? 'Trois tentatives infructueuses. Conformément à la politique de sécurité, le compte serait verrouillé et l’événement journalisé.'
            : 'Identifiant et mot de passe obligatoires (tentative ' + tentatives + ' sur 3).';
          return;
        }
        var role = sel.value;
        var compte = comptes.filter(function (x) { return x.identifiant === idField.value.trim(); })[0]
          || comptes.filter(function (x) { return x.role === role; })[0];

        /* Le rôle a-t-il été archivé depuis la matrice des droits ? Un compte
           rattaché à un rôle retiré ne doit pas ouvrir de session — et le refus
           doit être NOMMÉ : un écran qui se contenterait de ne rien faire
           laisserait croire à une panne. L'administrateur est informé. */
        if (N.roleArchive(role)) {
          refuserRoleArchive(role, compte);
          return;
        }

        S.setSession({
          role: role, nom: compte.nom, poste: N.ROLES[role].label, identifiant: compte.identifiant,
          fonction: compte.fonction, secteur: compte.secteur,
        });
        S.log('Connexion', 'M14', 'Session', compte.identifiant, null, { role: role });
        global.location.href = url(N.ROLES[role].home);
      });

      /* --------------------------------------------------------------------
       * Refus de connexion — rôle archivé.
       * L'administrateur retrouve la tentative dans « Rôles & permissions ».
       * ------------------------------------------------------------------ */
      function refuserRoleArchive(role, compte) {
        var libelle = N.ROLES[role] ? N.ROLES[role].label : role;
        S.collection('tentativesConnexion', { module: 'M14', entite: 'tentative', prefix: 'TNT' }).insert({
          identifiant: (compte && compte.identifiant) || idField.value.trim(),
          nom: (compte && compte.nom) || idField.value.trim(),
          role: role,
          motif: 'Rôle archivé — accès retiré par l’administrateur',
          horodatage: new Date().toISOString(),
          poste: 'Écran de connexion', traitee: false,
        });
        S.log('Connexion refusée', 'M14', 'Session', (compte && compte.identifiant) || idField.value.trim(),
          null, { role: role, motif: 'rôle archivé' });

        erreur.className = 'flex items-start gap-2 rounded-lg border border-danger-200 bg-danger-50 px-3 py-2';
        erreurTexte.textContent = 'Connexion refusée — le profil « ' + libelle + ' » a été retiré.';

        var m = U.modal({
          title: 'Connexion refusée', size: 'md',
          body: el('div.space-y-3', null, [
            el('div.flex.items-start.gap-3.rounded-lg.border.border-danger-200.bg-danger-50.p-3', null, [
              el('span.shrink-0.text-danger-600', null, C.icon('shield-x', 'h-5 w-5')),
              el('div.min-w-0', null, [
                el('p.text-sm.font-semibold.text-danger-900', { text: 'Ce compte ne peut plus ouvrir de session.' }),
                el('p.mt-1.text-xs.text-danger-800', {
                  text: 'Le profil « ' + libelle + ' » a été archivé par l’administrateur système. '
                    + 'Les habilitations rattachées à ce rôle sont suspendues.',
                }),
              ]),
            ]),
            U.descList([
              ['Compte', (compte && compte.nom) || idField.value.trim()],
              ['Profil demandé', libelle],
              ['Date et heure', C.dateHeure(new Date())],
              ['Suite donnée', 'La tentative est journalisée et signalée à l’administrateur.'],
            ], 'grid-cols-1'),
            el('p.text-xs.text-slate-500', {
              text: 'Pour retrouver l’accès, l’administrateur doit restaurer le rôle depuis '
                + '« Rôles & permissions », ou rattacher le compte à un autre profil.',
            }),
          ]),
          footer: [
            el('a.btn.btn-secondary', { href: url('contact-editeur') }, [C.icon('life-buoy', 'h-4 w-4'), 'Contacter l’assistance']),
            K.btn('Fermer', { variant: 'primary', onclick: function () { m.close(); } }),
          ],
        });
      }

      /* Pré-remplissage initial */
      idField.value = comptes[0].identifiant;
      pwField.value = 'demonstration';

      root.appendChild(shell({
        titre: 'Connexion',
        sousTitre: 'Authentification individuelle obligatoire — aucun compte partagé (CDCT §12.2).',
        body: form,
        pied: [
          el('span', { text: 'Pas encore de compte ? ' }),
          el('a.font-medium.text-navy-700.hover\\:underline', { href: url('auth-2fa'), text: 'Vérification en 2 étapes' }),
          el('span', { text: ' — ' }),
          el('a.font-medium.text-navy-700.hover\\:underline', { href: url('plan-du-site'), text: 'Plan du site' }),
        ],
      }));
      return null;
    },
  });

  /* ==========================================================================
   * MOT DE PASSE OUBLIÉ
   * ======================================================================== */
  global.SIGH.screen('auth-forgot', {
    standalone: true,
    render: function (root) {
      var f = el('form.space-y-4');
      f.appendChild(el('div', null, [
        el('label.label', { text: 'Identifiant ou adresse électronique' }),
        el('input.input', { type: 'text', placeholder: 'prenom.nom', required: true }),
      ]));
      f.appendChild(el('button.btn.btn-primary.btn-lg.w-full', { type: 'submit' }, 'Envoyer les instructions'));
      f.addEventListener('submit', function (e) {
        e.preventDefault();
        U.toast('Demande transmise à l’administrateur système.', {
          type: 'success', detail: 'La réinitialisation est effectuée par l’Administrateur (CDCT §12.2).',
        });
        setTimeout(function () { global.location.href = url('auth-reset'); }, 1200);
      });
      root.appendChild(shell({
        icon: 'key-round', titre: 'Mot de passe oublié',
        sousTitre: 'La réinitialisation est prise en charge par l’Administrateur système et journalisée.',
        body: f,
        pied: el('a.font-medium.text-navy-700.hover\\:underline', { href: url('index'), text: '← Retour à la connexion' }),
      }));
      return null;
    },
  });

  /* ==========================================================================
   * RÉINITIALISATION
   * ======================================================================== */
  global.SIGH.screen('auth-reset', {
    standalone: true,
    render: function (root) {
      var f = el('form.space-y-4');
      var pw = el('input.input', { type: 'password', required: true, placeholder: '••••••••' });
      var pw2 = el('input.input', { type: 'password', required: true, placeholder: '••••••••' });
      f.appendChild(el('div', null, [el('label.label', { text: 'Nouveau mot de passe' }), pw]));
      f.appendChild(el('div', null, [el('label.label', { text: 'Confirmer le mot de passe' }), pw2]));

      var regles = el('ul.space-y-1\\.5.rounded-lg.bg-slate-50.p-3');
      [['12 caractères minimum'], ['Au moins une majuscule et une minuscule'], ['Au moins un chiffre et un caractère spécial'],
       ['Renouvellement obligatoire tous les 90 jours']].forEach(function (r) {
        regles.appendChild(el('li.flex.items-center.gap-2.text-xs.text-slate-600', null, [
          C.icon('check', 'h-3.5 w-3.5 text-success-600'), el('span', { text: r[0] }),
        ]));
      });
      f.appendChild(regles);
      f.appendChild(el('button.btn.btn-primary.btn-lg.w-full', { type: 'submit' }, 'Définir le mot de passe'));
      f.addEventListener('submit', function (e) {
        e.preventDefault();
        if (pw.value !== pw2.value) { U.toast('Les deux mots de passe ne correspondent pas.', { type: 'error' }); return; }
        U.toast('Mot de passe mis à jour.', { type: 'success' });
        setTimeout(function () { global.location.href = url('index'); }, 1000);
      });
      root.appendChild(shell({
        icon: 'lock-keyhole', titre: 'Réinitialiser le mot de passe',
        sousTitre: 'Politique de mot de passe de la clinique (CDCT §12.2).',
        body: f,
        pied: el('a.font-medium.text-navy-700.hover\\:underline', { href: url('index'), text: '← Retour à la connexion' }),
      }));
      return null;
    },
  });

  /* ==========================================================================
   * DOUBLE FACTEUR (MFA)
   * ======================================================================== */
  global.SIGH.screen('auth-2fa', {
    standalone: true,
    render: function (root) {
      var f = el('form.space-y-4');
      var boxes = el('div.flex.justify-between.gap-2');
      var inputs = [];
      for (var i = 0; i < 6; i++) {
        var inp = el('input.input.h-14.w-full.text-center.text-xl.font-semibold', {
          type: 'text', inputmode: 'numeric', maxlength: 1, 'aria-label': 'Chiffre ' + (i + 1),
        });
        (function (idx, node) {
          node.addEventListener('input', function () {
            if (node.value && inputs[idx + 1]) inputs[idx + 1].focus();
          });
          node.addEventListener('keydown', function (e) {
            if (e.key === 'Backspace' && !node.value && inputs[idx - 1]) inputs[idx - 1].focus();
          });
        })(i, inp);
        inputs.push(inp);
        boxes.appendChild(inp);
      }
      f.appendChild(boxes);
      f.appendChild(el('button.btn.btn-primary.btn-lg.w-full', { type: 'submit' }, 'Vérifier'));
      f.appendChild(el('p.text-center.text-xs.text-slate-500', { text: 'Code non reçu ? Un nouvel envoi est possible dans 30 secondes.' }));
      f.addEventListener('submit', function (e) {
        e.preventDefault();
        var s = S.session();
        U.toast('Vérification réussie.', { type: 'success' });
        setTimeout(function () {
          global.location.href = url(s && s.role ? N.ROLES[s.role].home : 'dash-admin');
        }, 900);
      });
      root.appendChild(shell({
        icon: 'smartphone', titre: 'Vérification en 2 étapes',
        sousTitre: 'Exigée pour les profils à privilèges élevés : Administrateur et Direction (CDCT §12.2).',
        body: f,
        pied: el('a.font-medium.text-navy-700.hover\\:underline', { href: url('index'), text: '← Utiliser un autre compte' }),
      }));
      return null;
    },
  });

  /* ==========================================================================
   * ÉCRAN VERROUILLÉ
   * ======================================================================== */
  /* ==========================================================================
   * ÉCRAN VERROUILLÉ
   * --------------------------------------------------------------------------
   * Le verrouillage SUSPEND la session, il ne la ferme pas. C'est toute la
   * différence : au déverrouillage, l'agent retrouve l'écran qu'il avait
   * ouvert, à l'onglet près, et non un tableau de bord d'accueil qui lui
   * ferait tout recommencer.
   *
   * L'adresse de retour est posée par app.js au moment du verrouillage et
   * consommée ici — une seule fois, pour qu'un rechargement ultérieur de
   * l'écran verrouillé ne renvoie pas au hasard.
   * ======================================================================== */
  global.SIGH.screen('auth-lock', {
    standalone: true,
    render: function (root) {
      var s = S.session();
      var A = global.SIGH.app || {};
      var cleRetour = A.VERROU_RETOUR || 'sigh-cbg:verrou-retour';
      var retour = S.storage.get(cleRetour);

      /* Sans session, il n'y a rien à déverrouiller : on renvoie à la
         connexion plutôt que d'afficher un écran qui ne mène nulle part. */
      if (!s) {
        global.location.href = url('index');
        return null;
      }

      var ecranRetour = null;
      if (retour) {
        var id = String(retour).split('#')[0].replace(/\.html$/, '');
        ecranRetour = N.get(id);
      }

      var f = el('form.space-y-4');
      f.appendChild(el('div.flex.items-center.gap-3.rounded-lg.bg-slate-50.p-3', null, [
        el('span.grid.h-11.w-11.place-items-center.rounded-full.bg-navy-900.text-sm.font-semibold.text-white', { text: C.initials(s.nom) }),
        el('div.min-w-0', null, [
          el('p.text-sm.font-semibold.text-slate-900', { text: s.nom }),
          el('p.text-xs.text-slate-500', { text: N.ROLES[s.role] ? N.ROLES[s.role].label : '' }),
        ]),
      ]));

      /* Ce que l'agent va retrouver : le dire lève l'inquiétude de perdre
         la saisie en cours, qui est la première raison de désactiver un
         verrouillage automatique. */
      if (ecranRetour) {
        f.appendChild(el('div.flex.items-start.gap-2.rounded-lg.border.border-info-200.bg-info-50.px-3.py-2', null, [
          el('span.shrink-0.text-info-600', null, C.icon('history', 'h-4 w-4')),
          el('div.min-w-0', null, [
            el('p.text-xs.font-semibold.text-info-900', { text: 'Votre session est suspendue, pas fermée.' }),
            el('p.mt-0\.5.text-xs.text-info-800', {
              text: 'Au déverrouillage, vous reviendrez sur « ' + ecranRetour.label + ' ».',
            }),
          ]),
        ]));
      }

      var pw = el('input.input', { type: 'password', placeholder: '••••••••', required: true });
      f.appendChild(el('div', null, [
        el('label.label', { text: 'Mot de passe' }),
        pw,
      ]));
      f.appendChild(el('button.btn.btn-primary.btn-lg.w-full', { type: 'submit' }, [C.icon('unlock', 'h-4 w-4'), 'Déverrouiller']));

      f.addEventListener('submit', function (e) {
        e.preventDefault();
        S.log('Déverrouillage de session', 'M14', 'Session', s.identifiant || s.nom, null,
          { retour: retour || null });
        /* Le drapeau est à usage unique : sans cela, un rechargement de cet
           écran renverrait indéfiniment vers un écran quitté depuis. */
        S.storage.remove(cleRetour);
        if (retour) {
          global.location.href = A.base ? A.base() + retour : retour;
          return;
        }
        global.location.href = url(N.ROLES[s.role] ? N.ROLES[s.role].home : 'dash-admin');
      });

      /* ==================================================================
       * DÉCOR PROPRE AU VERROU (charte BAGUIDI, 02/09/2026) : plein écran
       * NOIR ANTHRACITE — le poste est en veille, pas en service — halos
       * rouge cœur et bleu santé, carte centrée frappée du logo circulaire
       * et de la double ligne de l'en-tête officiel, slogan en cursive.
       * ================================================================== */
      var scene = el('div.relative.flex.min-h-screen.items-center.justify-center.overflow-hidden.bg-gradient-to-br.from-anthracite-950.via-anthracite-900.to-sante-950.p-6');
      scene.appendChild(el('div.pointer-events-none.absolute.-left-24.-top-24.h-96.w-96.rounded-full.bg-sante-600\\/20.blur-2xl'));
      scene.appendChild(el('div.pointer-events-none.absolute.-bottom-28.-right-20.h-96.w-96.rounded-full.bg-coeur-500\\/15.blur-2xl'));
      scene.appendChild(el('div.pointer-events-none.absolute.-left-10.bottom-4.text-sante-500\\/10', null,
        C.icon('heart-pulse', 'h-64 w-64')));

      var carte = el('div.relative.w-full.max-w-md.overflow-hidden.rounded-2xl.bg-white.shadow-pop');
      var filet = el('div');
      filet.appendChild(el('div.h-\\[3px\\].bg-coeur-500'));
      filet.appendChild(el('div.h-\\[3px\\].bg-sante-600'));
      carte.appendChild(filet);

      var corps = el('div.p-8');
      corps.appendChild(el('div.mb-5.flex.flex-col.items-center.text-center', null, [
        el('span.grid.h-20.w-20.place-items-center.overflow-hidden.rounded-full.bg-white.ring-2.ring-coeur-500.ring-offset-2', null,
          el('img.h-\\[4\\.5rem\\].w-\\[4\\.5rem\\].rounded-full.object-contain', {
            src: base() + B.logo, alt: B.sigle,
            onerror: function () { this.replaceWith(C.icon('lock', 'h-8 w-8 text-navy-900')); },
          })),
        el('p.mt-3.font-heading.text-sm.font-bold.text-coeur-500', { text: B.nom }),
        el('p.font-slogan.text-lg.text-slate-500', { text: B.slogan }),
      ]));
      corps.appendChild(el('h2.text-center.text-2xl.font-semibold.tracking-tight.text-slate-900', { text: 'Session verrouillée' }));
      corps.appendChild(el('p.mt-1\\.5.text-center.text-sm.text-slate-500', {
        text: 'Verrouillage automatique après ' + Math.round((A.delaiVerrou ? A.delaiVerrou() : 900000) / 60000)
          + ' minutes d’inactivité sur les postes partagés (CDCT §12.2).',
      }));
      var zone = el('div.mt-6');
      zone.appendChild(f);
      corps.appendChild(zone);
      corps.appendChild(el('div.mt-6.text-center.text-sm.text-slate-500', null,
        el('a.font-medium.text-sante-700.hover\\:underline', {
          href: url('index'), text: 'Se connecter avec un autre compte',
          onclick: function () { S.setSession(null); S.storage.remove(cleRetour); },
        })));
      carte.appendChild(corps);
      scene.appendChild(carte);
      root.appendChild(scene);
      U.icons(root);
      return null;
    },
  });

  /* ==========================================================================
   * PAGES D'ERREUR
   * ======================================================================== */
  function pageErreur(id, code, titre, message, icon) {
    global.SIGH.screen(id, {
      standalone: true,
      render: function (root) {
        var wrap = el('div.flex.min-h-screen.flex-col.items-center.justify-center.p-6.text-center');
        wrap.appendChild(el('span.grid.h-16.w-16.place-items-center.rounded-2xl.bg-navy-50.text-navy-800', null, C.icon(icon, 'h-8 w-8')));
        wrap.appendChild(el('p.mt-6.text-5xl.font-bold.tracking-tight.text-navy-950', { text: code }));
        wrap.appendChild(el('h1.mt-2.text-xl.font-semibold.text-slate-900', { text: titre }));
        wrap.appendChild(el('p.mt-2.max-w-md.text-sm.text-slate-500', { text: message }));
        var actions = el('div.mt-6.flex.flex-wrap.justify-center.gap-2');
        var s = S.session();
        actions.appendChild(el('a.btn.btn-primary', { href: url(s && N.ROLES[s.role] ? N.ROLES[s.role].home : 'index') }, [C.icon('home', 'h-4 w-4'), 'Retour à l’accueil']));
        actions.appendChild(el('a.btn.btn-secondary', { href: url('plan-du-site') }, [C.icon('map', 'h-4 w-4'), 'Plan du site']));
        wrap.appendChild(actions);
        wrap.appendChild(el('p.mt-10.text-xs.text-slate-400', { text: B.nom + ' — SIGH-' + B.sigle }));
        root.appendChild(wrap);
        return null;
      },
    });
  }

  pageErreur('error-404', '404', 'Page introuvable',
    'L’écran demandé n’existe pas ou a été déplacé. Utiliser le plan du site pour retrouver le module recherché.', 'file-question');
  pageErreur('error-403', '403', 'Accès refusé',
    'Votre profil ne dispose pas des habilitations requises pour cet écran. L’accès est régi par la matrice RBAC (CDCT §12.1) et toute tentative est journalisée.', 'shield-x');

  /* ==========================================================================
   * PLAN DU SITE — inventaire complet des écrans
   * ======================================================================== */
  global.SIGH.screen('plan-du-site', {
    standalone: true,
    render: function (root) {
      var wrap = el('div.mx-auto.max-w-6xl.p-6');
      var head = el('div.mb-6.flex.flex-wrap.items-center.justify-between.gap-3');
      head.appendChild(el('div', null, [
        el('h1.text-2xl.font-semibold.tracking-tight.text-slate-900', { text: 'Plan du site' }),
        el('p.mt-1.text-sm.text-slate-500', { text: 'Inventaire de tous les écrans du prototype, organisés par domaine et par module.' }),
      ]));
      var s = S.session();
      head.appendChild(el('a.btn.btn-primary', { href: url(s && N.ROLES[s.role] ? N.ROLES[s.role].home : 'index') }, [C.icon('arrow-left', 'h-4 w-4'), 'Retour à l’application']));
      wrap.appendChild(head);

      var total = 0;
      N.NAV.forEach(function (domain) {
        var section = el('section.mb-6');
        section.appendChild(el('h2.mb-3.flex.items-center.gap-2.text-sm.font-semibold.uppercase.tracking-wide.text-slate-500', null, [
          C.icon(domain.icon, 'h-4 w-4'), domain.domain,
        ]));
        var grid = el('div.grid.gap-3.md\\:grid-cols-2.lg\\:grid-cols-3');
        domain.modules.forEach(function (mod) {
          var card = el('div.card');
          var body = el('div.card-body');
          body.appendChild(el('div.mb-2.flex.items-center.gap-2', null, [
            el('span.grid.h-7.w-7.place-items-center.rounded-lg.bg-navy-50.text-navy-700', null, C.icon(mod.icon, 'h-3.5 w-3.5')),
            el('span.text-sm.font-semibold.text-slate-800', { text: mod.label }),
            el('span.badge.badge-navy.font-mono', { text: mod.code }),
          ]));
          var ul = el('ul.space-y-0\\.5');
          mod.items.forEach(function (it) {
            total++;
            ul.appendChild(el('li', null,
              el('a.flex.items-center.gap-2.rounded.px-2.py-1.text-xs.text-slate-600.hover\\:bg-navy-50.hover\\:text-navy-800', {
                href: url(it.id),
              }, [
                C.icon(it.icon || mod.icon, 'h-3.5 w-3.5 shrink-0 text-slate-400'),
                el('span.truncate', { text: it.label }),
              ])));
          });
          body.appendChild(ul);
          card.appendChild(body);
          grid.appendChild(card);
        });
        section.appendChild(grid);
        wrap.appendChild(section);
      });

      /* Écrans hors navigation */
      var last = el('section');
      last.appendChild(el('h2.mb-3.text-sm.font-semibold.uppercase.tracking-wide.text-slate-500', { text: 'Accès et pages système' }));
      var ul2 = el('div.flex.flex-wrap.gap-2');
      N.STANDALONE.forEach(function (it) {
        ul2.appendChild(el('a.btn.btn-secondary.btn-sm', { href: url(it.id), text: it.label }));
      });
      last.appendChild(ul2);
      wrap.appendChild(last);

      wrap.appendChild(el('p.mt-8.text-xs.text-slate-400', {
        text: total + ' écrans métier recensés au manifeste, plus ' + N.STANDALONE.length + ' pages d’accès et système.',
      }));
      root.appendChild(wrap);
      return null;
    },
  });
})(window);
