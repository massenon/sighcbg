// Le barème de référence du régime employeur, tel que le JEU le porte (`referentiels.garanties`, daté) : les tests le lisent à la même source que le poste, jamais une copie.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

AssBareme baremeDuJeu() => AssBareme.depuis((jsonDecode(File('../../apps/poste/assets/donnees/jeu/referentiels.json').readAsStringSync()) as Map)['garanties']);
