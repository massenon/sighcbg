/// LE MOTEUR de l'assistant : question en français → [ReponseAst]. Il enchaîne la reconnaissance, le contrôle du DROIT (écrans de lecture de l'intention, dans la
/// matrice en force), les alertes de période, l'exécuteur, puis ne laisse sortir que des sources que l'agent VOIT.
///
/// Ce que le moteur ne fait jamais : écrire (le contexte n'a aucune fonction d'écriture), inventer (une lecture vide, une donnée manquante ou un droit absent se DISENT),
/// ouvrir le réseau (aucune importation de ce genre), conseiller sur un diagnostic. Toute exception d'un exécuteur devient un refus `ERREUR_INTERNE` sans détail
/// technique : une réponse fausse qui a l'air juste serait pire qu'un refus.
library;

import 'ast_catalogue.dart';
import 'ast_contexte.dart';
import 'ast_executeurs.dart';
import 'ast_reconnaissance.dart';

/// La longueur maximale d'une question lue : au-delà, le texte est tronqué (la reconnaissance ne gagne rien à lire un roman).
const int astQuestionMax = 400;

class AssistantAst {
  AssistantAst({CatalogueAst? catalogue, this.reglage = ReglageAst.complet}) : catalogue = catalogue ?? CatalogueAst();

  final CatalogueAst catalogue;
  final ReglageAst reglage;

  ReconnaisseurAst get reconnaisseur => ReconnaisseurAst(catalogue, reglage: reglage);

  ReponseAst repondre(String question, ContexteAst cx) {
    final q = question.length > astQuestionMax ? question.substring(0, astQuestionMax) : question;
    final rec = reconnaisseur.reconnaitre(q, aujourdhui: cx.jour);
    return depuisReconnaissance(rec, q, cx);
  }

  ReponseAst depuisReconnaissance(ReconnaissanceAst rec, String question, ContexteAst cx) {
    switch (rec.statut) {
      case 'refus':
        return _refus(rec, cx);
      case 'non_comprise':
        return ReponseAst(
            statut: 'non_comprise', code: 'INTENTION_INCONNUE', titre: 'Je n’ai pas compris la question',
            lignes: [refusAst['INTENTION_INCONNUE']!.motif[0].toUpperCase() + refusAst['INTENTION_INCONNUE']!.motif.substring(1) + ' : ${refusAst['INTENTION_INCONNUE']!.geste}.', ..._propositions(rec.propositions, cx)],
            propositions: _proposables(rec.propositions, cx), geste: refusAst['INTENTION_INCONNUE']!.geste);
      case 'ambigue':
        return ReponseAst(
            statut: 'ambigue', code: 'QUESTION_AMBIGUE', titre: 'Votre question peut vouloir dire plusieurs choses',
            lignes: ['Choisissez celle qui convient :', ..._propositions(rec.propositions, cx)], propositions: _proposables(rec.propositions, cx), geste: refusAst['QUESTION_AMBIGUE']!.geste);
      case 'precision_requise':
        return _precision(rec);
    }
    final id = rec.intention!;
    final i = catalogue[id];
    final exe = executeursAst[id];
    if (i == null || !i.actif || exe == null) {
      return const ReponseAst(statut: 'non_comprise', code: 'INTENTION_INCONNUE', titre: 'Cette question n’est pas disponible', lignes: ['Elle ne figure pas au catalogue livré.']);
    }
    // Le DROIT : au moins un écran de lecture de l'intention doit être vu. Aucun nom de rôle.
    if (i.ecransLecture.isNotEmpty && !cx.voit(i.ecransLecture)) {
      return ReponseAst(
          statut: 'refus', code: 'LECTURE_NON_AUTORISEE', intention: id, titre: 'Vous n’avez pas le droit de lire cette information',
          lignes: ['Cette question lit : ${i.ecransLecture.map(cx.ecran).join(' ou ')}. Votre profil n’en ouvre aucun.', 'Geste : ${refusAst['LECTURE_NON_AUTORISEE']!.geste}.'], geste: refusAst['LECTURE_NON_AUTORISEE']!.geste);
    }
    if (rec.alertes.contains('PERIODE_FUTURE')) {
      return ReponseAst(statut: 'refus', code: 'PERIODE_FUTURE', intention: id, titre: 'Cette période n’a pas commencé', lignes: ['Il n’y a rien à lire à une date qui n’est pas arrivée. Choisissez une période échue.'], geste: refusAst['PERIODE_FUTURE']!.geste);
    }
    if (rec.alertes.contains('NON_CALCULABLE_HISTORIQUE')) {
      return ReponseAst(
          statut: 'non_calculable', code: 'NON_CALCULABLE_HISTORIQUE', intention: id, titre: 'Non calculable : cet état n’est pas conservé à une date passée',
          lignes: ['Le logiciel ne garde que l’état d’aujourd’hui pour cette information ; le reconstituer reviendrait à l’inventer.', 'Je peux répondre pour aujourd’hui.'], geste: refusAst['NON_CALCULABLE_HISTORIQUE']!.geste);
    }
    ReponseAst rep;
    try {
      rep = exe(cx, rec, question);
    } catch (e) {
      // Aucun détail technique à l'écran : le refus est nommé, la cause se cherche dans le journal du poste.
      return ReponseAst(statut: 'refus', code: 'ERREUR_INTERNE', intention: id, titre: 'Je n’ai pas pu calculer cette réponse', lignes: ['Réessayez, ou ouvrez l’écran concerné.'], geste: refusAst['ERREUR_INTERNE']!.geste);
    }
    final visibles = [for (final s in rep.sources) if (cx.peutVoirEcran(s.ecran)) s];
    final renvoi = rep.ecranRenvoi;
    final pat = rep.statut == 'reponse' ? RegExp(r'\b([A-Z]{2,6}/\d+/\d{2})\b').firstMatch(rep.titre)?.group(1) : null;
    return rep.avec(sources: visibles, retirerRenvoi: renvoi != null && !cx.peutVoirEcran(renvoi), patientCode: pat, intention: id);
  }

  ReponseAst _refus(ReconnaissanceAst rec, ContexteAst cx) {
    final r = refusAst[rec.code] ?? refusAst['INTENTION_INCONNUE']!;
    final lignes = <String>['${r.motif[0].toUpperCase()}${r.motif.substring(1)}.'];
    String? renvoi;
    if (rec.code == 'ECRITURE_ABSENTE') {
      final e = rec.ecran;
      if (e != null && cx.peutVoirEcran(e)) {
        renvoi = e;
        lignes.add('Cet écran est « ${cx.ecran(e)} » : ouvrez-le et validez vous-même.');
      } else if (e != null) {
        lignes.add('L’écran concerné (« ${cx.ecran(e)} ») n’est pas dans votre périmètre : la personne habilitée le fera.');
      } else {
        lignes.add('Ouvrez l’écran concerné et validez vous-même.');
      }
    } else {
      lignes.add('Geste : ${r.geste}.');
    }
    return ReponseAst(statut: 'refus', code: r.code, titre: _titreRefus(r.code), lignes: lignes, geste: r.geste, ecranRenvoi: renvoi);
  }

  String _titreRefus(String code) => switch (code) {
        'ECRITURE_ABSENTE' => 'Je ne peux rien écrire : l’assistant est en lecture seule',
        'AVIS_MEDICAL_REFUSE' => 'Je ne donne ni diagnostic ni avis thérapeutique',
        'ENVOI_EXTERNE_REFUSE' => 'Rien ne quitte la clinique',
        'INJONCTION_REFUSEE' => 'Les règles et les droits ne se contournent pas',
        _ => 'Refusé',
      };

  ReponseAst _precision(ReconnaissanceAst rec) {
    final m = rec.manquants.isEmpty ? 'une précision' : rec.manquants.first;
    final titre = switch (m) {
      'patient' => 'De quel patient parlez-vous ?',
      'patient_ou_analyse' => 'De quel patient, ou de quelle demande (code NNNNN-AAAA), parlez-vous ?',
      'article' => 'De quel article parlez-vous ?',
      'acte' => 'De quel acte, analyse ou produit parlez-vous ?',
      'fournisseur' => 'De quel fournisseur parlez-vous ?',
      _ => 'Il me manque une précision',
    };
    final aide = switch (m) {
      'patient' => 'Donnez le code du dossier (forme CBG/rang/année) ou le nom.',
      'patient_ou_analyse' => 'Donnez le code du dossier (forme CBG/rang/année), le nom, ou le code de la demande d’analyse.',
      'article' => 'Donnez la désignation de l’article.',
      'acte' => 'Donnez le libellé de l’acte, de l’analyse ou du produit.',
      'fournisseur' => 'Donnez le nom ou le code du fournisseur.',
      _ => 'Reformulez en précisant.',
    };
    return ReponseAst(statut: 'precision', code: 'PRECISION_REQUISE', intention: rec.intention, titre: titre, lignes: [aide], geste: refusAst['PRECISION_REQUISE']!.geste);
  }

  /// Les intentions proposables à CE profil : un libellé n'est proposé que si l'agent a le droit de la lire (proposer une porte fermée).
  List<String> _proposables(List<String> ids, ContexteAst cx) => [
        for (final id in ids)
          if (catalogue.actif(id) && (catalogue[id]!.ecransLecture.isEmpty || cx.voit(catalogue[id]!.ecransLecture))) id
      ];

  List<String> _propositions(List<String> ids, ContexteAst cx) => [
        for (final id in _proposables(ids, cx)) '${catalogue[id]!.libelle}${catalogue[id]!.exemple.isEmpty ? '' : ' — par exemple : « ${catalogue[id]!.exemple} »'}'
      ];

  /// Les questions d'exemple que l'écran propose à l'accueil : une par intention livrée ET lisible par ce profil.
  List<String> exemples(ContexteAst cx) => [
        for (final i in catalogue.actives)
          if (i.exemple.isNotEmpty && (i.ecransLecture.isEmpty || cx.voit(i.ecransLecture))) i.exemple
      ];
}
