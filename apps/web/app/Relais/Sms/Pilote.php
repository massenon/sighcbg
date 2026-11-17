<?php

namespace App\Relais\Sms;

/**
 * ADR-0009 : le FOURNISSEUR de SMS est un pilote. Le relais ne connaît aucune API de fournisseur réel : un pilote reçoit un numéro au format international
 * et un texte déjà composé par la mère, et dit seulement si le fournisseur l'a accepté. Ses identifiants viennent du `.env` du relais, jamais du dépôt.
 */
interface Pilote
{
    public function nom(): string;

    public function envoyer(string $numero, string $texte): ResultatEnvoi;
}
