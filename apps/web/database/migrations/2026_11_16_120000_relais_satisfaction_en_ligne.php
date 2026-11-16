<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Les LIENS de satisfaction publiés par la mère. Le modèle de questions n'est pas secret (il est affiché à quiconque tient le lien) ; le jeton
        // n'est gardé que HACHÉ (sha256) : une copie de la base ne donne aucun lien valable. `ref` est l'identifiant de la fiche du lien au poste
        // (opaque pour le relais), rendu à la relève pour que la mère sache à quel lien appartient une enveloppe.
        Schema::create('satisfaction_liens', function (Blueprint $t) {
            $t->id();
            $t->string('jeton_hash', 64)->unique();
            $t->string('ref', 64);
            $t->string('clinique', 80);
            $t->string('titre', 120);
            $t->string('description', 500)->default('');
            $t->text('champs');                              // JSON : les champs engendrés par le générateur du domaine, publiés tels quels
            $t->string('cle_publique', 43);                  // X25519, base64url sans remplissage
            $t->string('kid', 16);
            $t->string('expire_le', 10);                     // AAAA-MM-JJ, inclus
            $t->unsignedBigInteger('revoque_le')->nullable(); // ms
            $t->unsignedBigInteger('publie_le');             // ms, dernière publication
            $t->string('jour_compte', 10)->default('');      // plafond par jour : le jour compté et son compte
            $t->unsignedInteger('n_jour')->default(0);
        });

        // Les ENVELOPPES déposées par les navigateurs : chiffrées, illisibles par le relais. Aucune adresse réseau, aucune heure fine : le jour de réception
        // seulement. Effacées dès que la mère en accuse la relève.
        Schema::create('satisfaction_enveloppes', function (Blueprint $t) {
            $t->id('rid');                                   // ordre de dépôt, pour une relève stable
            $t->string('id', 36)->unique();
            $t->unsignedBigInteger('lien_id');
            $t->string('enveloppe', 20000);
            $t->unsignedInteger('taille');
            $t->string('recue_le', 10);                      // AAAA-MM-JJ
            $t->index('lien_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('satisfaction_enveloppes');
        Schema::dropIfExists('satisfaction_liens');
    }
};
