<?php

namespace App\Relais\Sms;

/**
 * Un pilote qui dépend de paramètres du `.env`. `parametresManquants()` rend les NOMS des variables absentes (jamais leurs valeurs) : l'envoyeur ne
 * touche pas à la file tant qu'il en manque — une configuration incomplète ne doit pas brûler les cinq tentatives d'un SMS ni effacer son texte.
 */
interface PiloteConfigurable extends Pilote
{
    /** @return list<string> les noms des variables du `.env` qui manquent, dans l'ordre où l'on les renseigne. */
    public function parametresManquants(): array;
}
