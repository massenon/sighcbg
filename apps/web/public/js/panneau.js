/* Tiroir de navigation du panneau (sous 1024 px). Aucune dépendance : le relais tourne sur un hébergement sans npm ni CDN.
   Comportements : bouton menu, voile, fermeture au clic extérieur et à Échap, focus déplacé dans le tiroir puis rendu au bouton, boucle de Tab dans le tiroir,
   aria-expanded tenu à jour, tiroir refermé si la fenêtre repasse au-dessus de 1024 px.
   Sans JavaScript, la barre reste visible au-dessus de 1024 px ; en dessous, le tiroir ne s'ouvre pas (le panneau est un outil d'administration, JavaScript y est requis : Livewire l'exige déjà). */
(function () {
    'use strict';
    var coque = document.getElementById('coque');
    var barre = document.getElementById('barre');
    var bouton = document.getElementById('menu-ouvrir');
    var fermer = document.getElementById('menu-fermer');
    var voile = document.getElementById('voile');
    if (!coque || !barre || !bouton) { return; }
    var etroit = window.matchMedia('(max-width: 1023.98px)');
    var principal = [document.getElementById('contenu'), document.querySelector('.haut')];

    function focalisables() {
        return Array.prototype.slice.call(barre.querySelectorAll('a[href], button:not([disabled])'));
    }
    function ouvrir() {
        coque.classList.add('ouvert');
        bouton.setAttribute('aria-expanded', 'true');
        principal.forEach(function (n) { if (n) { n.setAttribute('inert', ''); } });
        var premier = barre.querySelector('[aria-current="page"]') || focalisables()[0];
        if (premier) { premier.focus(); }
    }
    function clore(rendreLeFocus) {
        if (!coque.classList.contains('ouvert')) { return; }
        coque.classList.remove('ouvert');
        bouton.setAttribute('aria-expanded', 'false');
        principal.forEach(function (n) { if (n) { n.removeAttribute('inert'); } });
        if (rendreLeFocus) { bouton.focus(); }
    }
    bouton.addEventListener('click', function () { if (coque.classList.contains('ouvert')) { clore(true); } else { ouvrir(); } });
    if (fermer) { fermer.addEventListener('click', function () { clore(true); }); }
    if (voile) { voile.addEventListener('click', function () { clore(true); }); }
    barre.addEventListener('click', function (e) { var a = e.target.closest ? e.target.closest('a[href]') : null; if (a && etroit.matches) { clore(false); } });
    document.addEventListener('keydown', function (e) {
        if (!coque.classList.contains('ouvert')) { return; }
        if (e.key === 'Escape') { e.preventDefault(); clore(true); return; }
        if (e.key !== 'Tab') { return; }
        var liste = focalisables();
        if (liste.length === 0) { return; }
        var premier = liste[0], dernier = liste[liste.length - 1];
        if (e.shiftKey && document.activeElement === premier) { e.preventDefault(); dernier.focus(); }
        else if (!e.shiftKey && document.activeElement === dernier) { e.preventDefault(); premier.focus(); }
    });
    var suivre = function () { if (!etroit.matches) { clore(false); } };
    if (etroit.addEventListener) { etroit.addEventListener('change', suivre); } else { etroit.addListener(suivre); }
})();
