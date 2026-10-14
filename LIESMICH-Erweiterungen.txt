Fishing Buddy 0.9.10-enhanced
=============================
Erweiterte Fassung fuer WoW 3.3.5a (WotLK) / AzerothCore

Basis ist Fishing Buddy 0.9.8p1 von Sutorix. Ergaenzt wurden:
Bugfixes, ein Auto-Angeln-Modul fuer Playerbots und eine
Sitzungs-Statistik.


1. Installation
---------------
Der Ordner im AddOns-Verzeichnis MUSS "FishingBuddy" heissen: der 3.3.5a-Client
laedt nur Interface/AddOns/<Ordner>/<Ordner>.toc. Ein "git clone" oder das
GitHub-ZIP liefert einen anderen Namen (fishing-buddy, fishing-buddy-main) --
dann taucht das AddOn nicht in der Liste auf und es gibt keine Fehlermeldung.

    cd "<WoW-Verzeichnis>/Interface/AddOns"
    git clone https://github.com/nexartgroup/fishing-buddy FishingBuddy

Danach WoW komplett neu starten -- ein /reload reicht nicht, wenn sich die
TOC-Datei geaendert hat.

Alte gespeicherte Daten (Fische, Fundorte, Outfits) bleiben erhalten, es wird
nichts geloescht.


2. Auto-Angeln ueber Playerbot
------------------------------

2.1 Wie es funktioniert
-----------------------
Der WoW-Client von 3.3.5a laesst es nicht zu, dass ein AddOn selbstaendig
Zauber wirkt -- die dafuer noetigen Funktionen sind geschuetzt und brauchen
einen echten Mausklick oder Tastendruck. Ein AddOn kann also nicht von sich aus
die Angel auswerfen.

Was ein AddOn darf: Chat- und Server-Befehle senden. Darauf setzt dieses Modul
auf. Es steuert den "Selbstbot" von mod-playerbots (".playerbots bot self"): der
Server spielt dann den eigenen Charakter und wirft auf Befehl die Angel aus.

Betriebsart "Schleife": Der Spieler stellt den Charakter dort ab, wo geangelt
werden soll (10 bis 20 Meter vom Wasser, mit Sichtlinie). Ein Klick auf
Auto-Angeln startet dann eine Schleife, die laeuft, bis das Auto-Angeln wieder
ausgeschaltet wird. Frueher wurde dem Bot nur die Strategie "master fishing"
gegeben und ihm das Angeln ueberlassen; das AddOn steuert jetzt jeden Wurf selbst:

  1. Koeder      Ist ein Koeder in den Taschen, aber keiner aufgetragen (weniger
                 als 30 Sekunden Restlaufzeit), wird er aufgetragen (s. 2.5).
  2. Platz       Fluestern an den eigenen Charakter:  do move near water
                 (setzt den Angelplatz; steht der Charakter schon am Wasser,
                 bleibt er stehen)
  3. Auswerfen   Fluestern an den eigenen Charakter:  do go fishing
  4. Warten      bis der Fisch gefangen ist: der Charakter kanalisiert "Angeln";
                 endet das (Biss und Schwimmer eingeholt, oder die Zeit lief ab),
                 wartet das AddOn kurz auf den Fang und beginnt bei 1. von vorn.

Eigenheiten des Servers, die das bestimmen (nachgelesen im Quelltext von
AzerothCore und mod-playerbots; im Spiel NICHT ausprobiert -- ausser dass die
beiden "do"-Befehle von Hand funktionieren):

  * Befehle an den Selbstbot gehen als Fluestern an den eigenen Namen. "/p ..."
    waere falsch: der Server verwirft Gruppenchat eines Spielers ohne Gruppe
    stillschweigend (ChatHandler.cpp).
  * "do <Aktion>" fuehrt der Bot SOFORT beim Eintreffen des Fluesterns aus
    (PlayerbotAI::HandleCommand ruft DoSpecificAction direkt auf), nicht erst im
    KI-Takt -- auch ein frisch eingeschalteter Bot, der sonst rund 10 Sekunden
    lang nichts liest, und ein Bot, der gerade auf den Schwimmer wartet.
  * "go fishing" funktioniert nur, wenn "move near water" den Angelplatz gesetzt
    hat und der Charakter genau dort steht. Laeuft der Bot erst zum Ufer
    ("move near water" findet Wasser bis etwa 30 Meter ausserhalb der
    Sichtlinie, FishingDistanceFromMaster + 20), schlaegt der erste Versuch fehl
    und der naechste Durchgang wirft aus.
  * Den Schwimmer holt der Bot selbst ein: "go fishing" schaltet dafuer die
    Strategie "use bobber" ein (FishingAction::Execute).
  * Fehlermeldungen des Bots ("go fishing: useless" und Aehnliches) erreichen
    einen Selbstbot NICHT (PlayerbotAI::TellError verwirft sie, wenn der Master
    selbst ein Bot ist). Das AddOn erkennt einen Fehlschlag deshalb nur daran,
    dass nach dem Befehl keine Kanalisierung beginnt.
  * Der Bot behaelt von allen "nc"-Befehlen eines KI-Taktes nur den LETZTEN.
    Deshalb geht jede Strategieaenderung als EIN Befehl hinaus, z. B.
    "nc ?,-mount,-master fishing,?" (die beiden "?" lassen den Bot seine
    Strategieliste vor und nach der Aenderung nennen).

Beim Start passiert, in dieser Reihenfolge:

  1. "nc ?"      Der Bot wird nach seinen Strategien gefragt (3 s Wartezeit,
                 18 s, wenn der Charakter gerade angelt). Antwortet er, ist der
                 Selbstbot schon an und wird NICHT umgeschaltet.
  2. Umschalten  Nur wenn er nicht antwortet, geht ".playerbots bot self" hinaus.
                 Das ist ein Umschalter; das AddOn liest die Antwort des Servers
                 ("SelfBot is now active." / "... deactivated." / Verweigerung).
                 Lautet sie "deactivated", war der Bot schon an (nur noch taub):
                 dann wird ein zweites Mal geschaltet, und der Bot gilt nicht
                 als vom AddOn eingeschaltet.
  3. Vorbereitung  Nur wenn noetig, EIN Befehl: "-mount" (s. 2.6) und
                 "-master fishing" (eine uebrig gebliebene Strategie der alten
                 Betriebsart oder von Hand gesetzt: sie wuerde auf eigene Faust
                 angeln und der Schleife dazwischenfunken). Kennt das AddOn die
                 Strategieliste des Bots noch nicht (frisch eingeschalteter
                 Bot), steht davor eine Abfrage "?", danach immer eine. Auf die
                 Antwort wird bis zu 25 s gewartet (nach dem Einschalten; 20 s
                 bei einem Bot, der schon lief); bis zu drei Versuche, dann
                 Abbruch mit Meldung (und der Bot wird wieder ausgeschaltet,
                 sofern das AddOn ihn eingeschaltet hat). Ist nichts
                 vorzubereiten, geht es ohne Befehl sofort los.
  4. Schleife    Erst jetzt steht im Chat "Auto-Angeln gestartet." und der erste
                 Wurf folgt. Zeigt der Client die Antworten des Bots nie an, gilt
                 der Start nach der Wartezeit als "nicht bestaetigt" (mit
                 Warnung); die Schleife laeuft trotzdem.

Beim Stoppen endet die Schleife sofort; ein Wurf, der gerade laeuft, wird nicht
abgebrochen (der Client darf das nicht), der Bot holt den Schwimmer noch ein,
solange er an ist. Eine Rueckname geht nur hinaus, wenn etwas zurueckzugeben ist
("mount", s. 2.6) oder wenn der Block "Beim Stoppen" geaendert wurde: als EIN
Befehl ("nc +mount,-master fishing,?"), der alle drei Sekunden wiederholt wird, bis
die Liste ihn bestaetigt (hoechstens 24 s). ERST DANN wird der Bot ausgeschaltet,
und nur, wenn das AddOn ihn selbst eingeschaltet hat. Ist nichts zurueckzugeben,
geschieht das sofort. Wer den Selbstbot schon vorher an hatte (Botpad,
AutoTravel, Servereinstellung), behaelt ihn an. Auch waehrend einer
AutoTravel-Reise, die sich auf den Selbstbot verlaesst, bleibt er an. Hat jemand
anderes den Selbstbot waehrenddessen ausgeschaltet, wird er nicht wieder
eingeschaltet.

Abmelden und /reload waehrend des Angelns: die Rueckname geht noch hinaus, den
Bot auszuschalten wird aber nicht im selben Atemzug versucht (der Server
verwirft dabei die noch wartende Anweisung). Stattdessen merkt sich das AddOn,
dass etwas aufzuraeumen ist ("AutoFishPending" in den gespeicherten Daten, mit
der Angabe, ob "mount" zurueckgegeben werden muss). Nach dem naechsten Anmelden
schaut es nach (bis zu 14 s, ein frisch eingeschalteter Bot hoert erst nach etwa
10 s zu) und raeumt auf. Antwortet der Bot nicht, weil er aus ist, bleibt der
Vermerk (bis zu fuenf Anmeldungen lang) und wird abgearbeitet, sobald der Bot
das naechste Mal eingeschaltet wird oder ein neuer Lauf beginnt; der neue Lauf
uebernimmt den Vermerk und gibt "mount" am Ende zurueck. Bei einem echten
Abmelden erreicht die Rueckname den Server unter Umstaenden nicht mehr (der
Bot wird mit dem Abmelden abgebaut): dann bleibt "mount" entfernt, bis das
Aufraeumen es zurueckgibt. Dasselbe gilt, wenn jemand den Selbstbot von aussen
ausschaltet, waehrend "mount" entfernt ist (z. B. "BOT AUS" in Botpad): auch
dann wird ein Vermerk gespeichert.

2.2 Bedienung
-------------
  Panel-Button   Linksklick startet/stoppt, Rechtsklick oeffnet
                 die Einstellungen. Das Panel laesst sich mit der
                 Maus frei verschieben.

  /fb auto           an-/ausschalten
  /fb auto on        starten
  /fb auto off       stoppen
  /fb auto lure      automatisches Koeder-Auftragen umschalten
  /fb auto edit      Befehls-Editor oeffnen
  /fb auto panel     Panel ein-/ausblenden
  /fb auto status    aktuellen Stand im Chat ausgeben
  /fb auto diag      Fehlersuche: Zustand des Selbstbots, die Phase der
                     Schleife, die Strategieliste des Bots,
                     Gruppe/Reittier/Botpad/AutoTravel und die letzten
                     gesendeten und empfangenen Zeilen (mit Zeitangabe)
  /fb auto probe     fragt den Bot nach seinen Strategien (Antwort in "diag")

  Tastenbelegung   "Auto-Angeln umschalten" und "Auto-Angeln-Panel
                   umschalten" stehen in den Tastaturbelegungen
                   unter "Fishing Buddy" bereit.

  Makro            /run FishingBuddy_ToggleAutoFishing()

Nach "Stopp" laeuft eine noetige Rueckname noch einige Sekunden (siehe oben); in
dieser Zeit meldet ein neuer Start "Der Bot wird noch gestoppt, einen Moment
bitte." und tut nichts. (Nur das Aufraeumen nach dem Anmelden, das auf einen
stummen Bot wartet, wird von einem neuen Start abgeloest.)

2.3 Die Befehle anpassen
------------------------
Unter "/fb auto edit" stehen frei editierbare Bloecke, ein Befehl pro Zeile.
Der Umschalter ".playerbots bot self" gehoert NICHT hinein: das AddOn schaltet
selbst und nur bei Bedarf. (Steht die Zeile noch in einem gespeicherten Block,
wird sie beim Ausfuehren uebersprungen und das gemeldet. Bloecke, die noch genau
dem alten Standard entsprechen, werden beim Laden durch den neuen Standard
ersetzt.)

  Angel-Schleife    vor JEDEM Wurf gesendet
  Beim Stoppen      vor dem Ausschalten gesendet (nur wenn etwas zurueckzugeben
                    ist oder der Block geaendert wurde, s. 2.1)
  Koeder auftragen  wird gesendet, wenn der Koeder ablaeuft

Die frueheren Bloecke "Beim Start" und "Neu setzen" der Strategie-Betriebsart
gibt es nicht mehr; ihre gespeicherten Werte werden nicht mehr benutzt. Eigene
Zeilen daraus gehoeren jetzt in die Angel-Schleife.

Voreingestellt sind:

  Schleife:    /w %p do move near water
               /w %p do go fishing
  Stopp:       /w %p nc -master fishing
  Koeder:      /w %p u %l

Regeln fuer die Zeilen:

  /w %p do ...  erreicht den eigenen Selbstbot und wird sofort ausgefuehrt.
  /w %p nc ...  erreicht den eigenen Selbstbot. ALLE "nc"-Zeilen eines Blocks
                (auch mehrere, auch mit Kommalisten) fasst das AddOn zu einem
                einzigen Befehl zusammen, weil der Bot je Takt nur einen
                "nc"-Befehl behaelt. Die Reihenfolge bleibt erhalten; der
                zusammengefasste Befehl geht vor den uebrigen Zeilen hinaus.
  .befehl       geht als Server-Befehl raus (Punkt am Anfang)
  /w NAME text  Fluestern an jemand anderen
  /p text       Gruppenchat (ebenso /s /y /g /o /ra /rw /bg /1 ...).
                Ausnahmen: "/p nc ..." geht immer an den eigenen Selbstbot,
                und OHNE Gruppe geht jede /p-Zeile als Fluestern an den
                eigenen Selbstbot (der Server wuerde Gruppenchat ohne Gruppe
                verwerfen); das wird einmal gemeldet. Nur in einer Gruppe geht
                eine andere /p-Zeile an die Gruppe.
  /sonstiges    wird als normaler Slash-Befehl ausgefuehrt
  -- text       Kommentarzeile, wird uebersprungen

Alle Zeilen der Schleife laufen vor jedem Wurf, also oft: Zeilen, die in den
Chat sprechen, tun das bei jedem Wurf. Ein Wort zu "nc !": der Server wendet
"!" erst NACH allen anderen Teilen desselben Befehls an. Eine Zeile "nc !"
gefolgt von "nc +gather" im selben Block setzt also die Strategie gleich wieder
zurueck; ein Rueckstellungsbefehl gehoert nicht in diese Bloecke.

Platzhalter:  %p = eigener Charaktername, %z = Zone, %s = Unterzone

Die Fluesterzeilen an sich selbst (und die Antworten des Bots) blendet das AddOn
aus dem Chat aus ("Bot-Fluestern im Chat ausblenden", in den Optionen). Das
gilt fuer das normale Chatfenster; Addons, die Fluestern selbst mitschneiden,
und ein GM-Chatfenster zeigen sie weiter an, und ein "Abwesend"- oder
"Nicht stoeren"-Status antwortet unter Umstaenden auf das eigene Fluestern.

AFK: Nach fuenf Minuten ohne Tastatur- oder Mauseingabe setzt der Client den
Charakter selbst auf AFK, und das kann ein AddOn nicht verhindern (Eingaben
darf es nicht erzeugen). Der Server antwortet dann auf JEDES Fluestern an den
Charakter -- auch an sich selbst -- mit einer Systemmeldung ("... ist AFK:
..."), bei der Schleife zweimal je Wurf. Diese Meldungen blendet das AddOn mit
derselben Option aus. Den AFK-Status selbst laesst es stehen: mod-playerbots
lehnt die automatische Abmeldung nach 30 Minuten ohne Eingabe nur ab, solange
der Selbstbot AFK ist (PlayerbotsSelfBotAfk.cpp); wuerde das AddOn AFK per
"/afk" loeschen, ginge diese Abmeldung durch.

2.4 Die Ueberwachung
--------------------
Solange das Auto-Angeln laeuft, prueft das AddOn alle zwei Sekunden:

  * Angel noch angelegt?        sonst Stopp
  * Charakter tot?              sonst Stopp
  * Kampf begonnen?             Stopp (abschaltbar)
  * Taschen voll?               Stopp oder Warnung (einstellbar)
  * Zeitlimit erreicht?         Stopp (0 = kein Limit)
  * Koeder abgelaufen?          wird vor dem naechsten Wurf aufgetragen, sonst
                                Warnung mit Ton
  * Selbstbot ausgeschaltet?    Stopp mit Meldung (jemand hat ihn abgeschaltet)
  * Im Sattel?                  Warnung; die Schleife wirft solange nicht aus
                                (im Sattel kann nicht geangelt werden)

Die Schleife selbst merkt, wenn der Bot nicht auswirft: fuenf Versuche in Folge,
auf die innerhalb von etwa 5 Sekunden keine Kanalisierung folgt (der Bot, der
zum Ufer laeuft, zaehlt nicht), beenden das Auto-Angeln mit der Meldung, dass
der Bot nicht auswirft. Waehrend einer AutoTravel-Reise ruht die Schleife.

2.5 Koeder automatisch auftragen
--------------------------------
Es gibt drei Wege, den Koeder zu erneuern. Der erste ist vollautomatisch, die
anderen beiden brauchen einen Tastendruck beziehungsweise einen Klick.

(1) Ueber den Bot  --  Einstellung "Koeder vom Bot auftragen lassen"

    Faellt der Koeder unter 30 Sekunden Restlaufzeit (oder ist keiner da und
    einer in den Taschen), schickt die Schleife VOR dem naechsten Wurf den
    Befehl aus dem Block "Koeder auftragen" an den Bot und wartet bis zu 8
    Sekunden auf den neuen Koeder (das Auftragen dauert 5 s). Waehrend das
    laeuft, wird nicht geangelt -- ein Gegenstand laesst sich nicht
    benutzen, solange der Charakter kanalisiert.

    Voreingestellt ist:   /w %p u %l

    Platzhalter in diesem Block:
        %l = Itemlink des Koeders
        %i = Item-ID
        %n = Name des Koeders

    Ob dein Playerbot-Build den "use"-Befehl kennt, muss sich zeigen. Das AddOn
    merkt es selbst: klappt es nach drei Versuchen nicht, gibt es auf, sagt
    Bescheid, angelt ohne Koeder weiter und faellt auf die manuellen Wege
    zurueck. Nach einem "/fb auto lure" (aus und wieder an) oder einem von Hand
    aufgetragenen Koeder probiert es erneut.

(2) Per Taste

    In den Tastaturbelegungen gibt es unter "Fishing Buddy" den Eintrag
    "Besten Koeder auftragen". Ein Druck auf die Taste traegt den Koeder auf --
    ohne Maus, ohne Fenster.

    Technischer Hintergrund: das AddOn liest die belegte Taste aus und legt sie
    per SetOverrideBindingClick direkt auf den sicheren Button. Nur so laesst
    WoW eine geschuetzte Aktion per Tastendruck zu.

(3) Per Klick

    Rechts im Panel sitzt der Koeder-Knopf. Wird ein Koeder faellig, faengt er
    gruen an zu pulsieren. Der Tooltip zeigt, welcher Koeder genommen wird,
    wieviel Bonus er bringt und welche Taste belegt ist. Ist nichts Passendes in
    den Taschen, ist der Knopf ausgegraut.

Warum nicht einfach immer automatisch? Der WoW-Client von 3.3.5a laesst die
Benutzung von Gegenstaenden nur als Reaktion auf einen echten Tastendruck oder
Mausklick zu. Ein AddOn, das den Koeder von sich aus aus dem Nichts auftraegt,
ist technisch nicht moeglich -- deshalb der Umweg ueber den Bot.

2.6 Reittier
------------
Ein Selbstbot hat standardmaessig die Strategie "mount": hat der Charakter ein
Reittier (und Stufe 20 oder mehr), steigt er im Leerlauf von selbst auf, und im
Sattel laesst sich nicht angeln. Mit der Option "Bot nicht aufsitzen lassen"
(Standard an) steht "-mount" schon im Vorbereitungsbefehl vor dem ersten Wurf,
und beim Stoppen kommt "+mount" zurueck -- aber nur, wenn die Strategie vorher in
der Liste des Bots stand. Wer beim Start schon im Sattel sitzt, bekommt einen
Hinweis und das Auto-Angeln startet nicht. Steigt der Charakter spaeter auf,
wirft die Schleife nicht aus, bis er wieder absteigt.

2.7 Zusammenspiel mit Botpad und AutoTravel
-------------------------------------------
Botpad (bis 1.2) setzt bei JEDER Meldung "SelfBot is now active." seinen Modus
(nc !, co !, ...) und nahm im Modus "Minimal" ausserdem die Chat-Strategie weg,
der Bot wurde taub fuer Chatbefehle. Ab Botpad 1.3 bittet das AddOn Botpad per
Botpad.Bot.Hold("Fishing Buddy") um Zurueckhaltung, solange das Auto-Angeln
laeuft (Release beim Stoppen). Bei einem aelteren Botpad wartet das AddOn nach
dem Einschalten 3,5 s, bis dessen Salve vorbei ist, und warnt bei "Minimal" vor
dem Problem (Botpad aktualisieren). Schlaegt der Hold-Aufruf fehl, wird wie bei
einem aelteren Botpad gewartet. Kommt es trotzdem durcheinander: "/bp
freigeben" in Botpad.

AutoTravel setzt zu Reisebeginn eigene Strategien (nc !) und bewegt den
Charakter. Waehrend einer Reise laesst das AddOn den Bot in Ruhe und startet
nicht; danach macht die Schleife von selbst weiter. Ist beides geladen,
schaltet AutoTravel den Selbstbot fuer die Reise ein -- das Auto-Angeln erkennt
das (der Bot antwortet auf "nc ?") und schaltet nicht um.

2.8 Wenn nichts geangelt wird
-----------------------------
  1. Steht im Chat "Fishing Buddy ... loaded"? Wenn nicht, ist das AddOn nicht
     geladen: Ordnername (muss "FishingBuddy" sein), Version der TOC, und mit
     /console scriptErrors 1 nach Lua-Fehlern sehen.
  2. /fb auto diag  zeigt, was passiert ist:
       "Selbstbot aus" (englisch "self bot off") und eine Verweigerung im Verlauf -> der Server erlaubt den
         Selbstmodus nicht (Playerbots.SelfBotLevel: 0 = aus, 1 = nur
         Spielleiter, 2 = alle, mehr = zusaetzlich beim Anmelden automatisch).
       Keine Strategieliste -> der Bot antwortet nicht. Spielleiter-Konten haben
         Fluestern aus, bis ".whispers on" eingegeben wurde. Hat jemand mit "-chat"
         die Chatbefehle abgeschaltet (oder Botpad bis 1.2 im Modus "Minimal"),
         hilft Aus- und wieder Einschalten; Botpad auf 1.3 bringen. Ein frisch
         eingeschalteter Bot antwortet erst nach etwa 10 Sekunden.
       "Schleife: Phase cast, ... Fehlversuche in Folge: N" -> die Befehle gehen
         hinaus, aber der Bot wirft nicht aus. Siehe Punkt 3.
  3. Die beiden Befehle von Hand ausprobieren (Chat, Fluestern an den eigenen
     Namen):  /w <Name> do move near water  und danach  /w <Name> do go fishing
     Wirft der Bot dann aus, liegt es am Ablauf des AddOns (bitte "/fb auto
     diag" ansehen). Wirft er nicht aus, liegt es am Bot: kein angelbares Wasser
     in 10 bis 20 Metern (mit Sichtlinie), Reittier, Kampf, Schwimmen, keine
     Angel (dann meldet er "I don't have a Fishing Pole"). Der Bot sucht Wasser
     aus der Entfernung nur bis rund 30 Meter und nur innerhalb der
     Servereinstellung Playerbots.FishingDistanceFromMaster (Standard 10).
  4. Der Server speichert die Strategien des Bots. Hat eine fruehere Fassung
     (oder jemand von Hand) "master fishing" gespeichert, nimmt der Start sie
     heraus; von Hand: "/w <Name> nc -master fishing" bei eingeschaltetem
     Selbstbot.

2.9 Grenzen
-----------
  * Alles oben ist gegen Quelltext und ein nachgebautes Modell geprueft, NICHT
    in einem echten Client gegen einen echten Server. Die Wartezeiten stammen
    aus dem Quelltext des Servers; "/fb auto diag" zeigt, wie es sich tatsaechlich
    verhaelt.
  * Das AddOn sieht nur, DASS ausgeworfen wird (der Charakter kanalisiert), nicht
    warum es nicht klappt: der Server schickt einem Selbstbot keine
    Fehlermeldungen.
  * Hat jemand den Selbstbot von aussen ausgeschaltet oder wurde abgemeldet,
    bevor die Rueckname ankam, kann "mount" in den gespeicherten Strategien des
    Bots fehlen. Das AddOn merkt es sich und raeumt auf, sobald der Bot wieder
    zuhoert (s. 2.1).


3. Sitzungs-Statistik
---------------------
Neu ist eine laufende Auswertung der aktuellen Angel-Sitzung.

Im Watcher-Fenster (zusaetzliche Zeilen, einzeln abschaltbar):

  Rate            Faenge pro Stunde
  Trefferquote    Anteil erfolgreicher Wuerfe
  Wert            geschaetzter Haendlerwert, gesamt und pro Stunde
  Koeder          Restlaufzeit, faerbt sich orange und dann rot

Ausfuehrlich im Chat mit "/fb stats":

  Angelzeit, Faenge, entkommene Fische, Trefferquote,
  Faenge pro Stunde, Haendlerwert, erbeutetes Gold,
  Skillanstieg, bester Fang und die fuenf haeufigsten Fische
  mit Prozentanteil.

  /fb stats reset    Zaehler zuruecksetzen

Optional laesst sich der Bericht automatisch ausgeben, sobald man
die Angel wieder ablegt oder das Auto-Angeln endet.

Hinweis: der Haendlerwert stammt aus dem Item-Cache des Clients.
Fuer Items, die der Client in dieser Sitzung noch nie gesehen hat,
kann er kurzzeitig fehlen und wird dann mit 0 gewertet.


4. Behobene Fehler der Originalversion
--------------------------------------

FishingSchools.lua, Zeile 55
    Astrolabe:ComputeDistance(C, Z, x, x, ...) -- die y-Koordinate
    wurde durch x ersetzt. Der Abstand zu bereits bekannten
    Fischschwaermen wurde dadurch falsch berechnet, sodass
    derselbe Schwarm mehrfach in der Datenbank landete.
    Korrigiert zu (C, Z, x, y, ...).

FishingSchools.lua, Zeile 130
    "for i in pairs(1,c) do" ist zwar gueltige Syntax, wirft aber
    zur Laufzeit einen Fehler, weil pairs() eine Tabelle erwartet.
    CollapseHoles() war damit komplett unbrauchbar.
    Korrigiert zu "for i=1,c do".

FishingWatcher.lua, UpdateUnknownZone()
    Zugriff auf fh[sidx] statt fh[zmto(zidx, sidx)]. sidx ist nur
    der Unterzonen-Index, nicht der gepackte Zonen-Marker -- die
    Funktion schrieb in den falschen Eintrag beziehungsweise lief
    auf einen nil-Zugriff. Zusaetzlich wird das Ziel jetzt angelegt,
    falls es noch nicht existiert.

FishingWatcher.lua, SetEntry() und VARIABLES_LOADED
    "entry" und "lastSkillMax" waren versehentlich globale
    Variablen. Beide sind jetzt lokal, damit sie nicht mit anderen
    AddOns kollidieren.

FishingBuddy.toc
    localization.ruRU.lua war zwar im Paket enthalten, wurde aber
    nie geladen. Jetzt eingetragen.


5. Neue Schnittstellen fuer eigene Erweiterungen
------------------------------------------------
  FBConstants.WATCHER_LINES_EVT
      handler(tabelle) -- eigene Zeilen per tinsert() in die
      Watcher-Anzeige einhaengen

  FBConstants.AUTO_START_EVT / AUTO_STOP_EVT
      werden beim Start und Stopp des Auto-Angelns ausgeloest

  FishingBuddy.API.GetBestLure()
      liefert den besten momentan sinnvollen Koeder als Tabelle
      ({ id, n, b, s, d }) oder nil

  FishingBuddy.API.GetLureInventory()
      liefert die beiden Listen der verfuegbaren Koeder und
      Verbrauchsgegenstaende

  FishingBuddy.Auto.Start() / Stop() / Toggle() / IsRunning()
  FishingBuddy.Stats.Get() / Reset() / PrintReport()


6. Hinweis
----------
Das Auto-Angeln steuert ausschliesslich die Playerbot-Funktion des
eigenen Servers -- es automatisiert nichts am Client vorbei und
funktioniert nur dort, wo der Server die entsprechenden Befehle
auch annimmt. Auf offiziellen Realms hat es keine Wirkung.


7. Offline-Tests
----------------
Ohne Spiel pruefbar sind das Laden, die Zustandsfolge des Auto-Angelns und der
Umgang mit den Antworten eines nachgebauten Servers:

    tests/run.sh .          (im Hauptverzeichnis; Lua 5.1, optional luacheck)

tests/README.txt beschreibt, was das prueft und was NICHT: es ist kein
WoW-Client und kein echter Server. Ob eine Aussage im Spiel stimmt, zeigt
"/fb auto diag".
