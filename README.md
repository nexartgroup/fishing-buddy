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
Server spielt dann den eigenen Charakter, und die Strategie "master fishing"
laesst ihn angeln. Das AddOn schaltet den Selbstbot ein, setzt die Strategie,
prueft anhand der Antwort des Bots, ob sie wirklich angekommen ist, und
ueberwacht danach den Ablauf.

Drei Eigenheiten des Servers bestimmen den Ablauf (nachgelesen im Quelltext von
AzerothCore und mod-playerbots; im Spiel NICHT ausprobiert):

  * Befehle an den Selbstbot gehen als Fluestern an den eigenen Namen. "/p ..."
    waere falsch: der Server verwirft Gruppenchat eines Spielers ohne Gruppe
    stillschweigend (ChatHandler.cpp). Die Fassung 0.9.9 sendete "/p nc ..." und
    lief deshalb nur in einer Gruppe -- ohne Gruppe geschah gar nichts.
  * Der Bot liest seine Chatbefehle nur in seinem KI-Takt und behaelt von allen
    "nc"-Befehlen eines Taktes nur den LETZTEN. Zwei schnell nacheinander
    gefluesterte "nc"-Zeilen heben sich also auf. Deshalb geht jede Aenderung
    als EIN Befehl hinaus, z. B.  "nc ?,-mount,+master fishing,?"  (die beiden
    "?" lassen den Bot seine Strategieliste vor und nach der Aenderung nennen).
  * Ein frisch eingeschalteter Selbstbot hoert etwa 10 Sekunden lang auf keinen
    Chatbefehl, und ein angelnder Bot schlaeft waehrend der Wartezeit auf den
    Schwimmer (rund 15 bis 17 Sekunden). Deshalb sind die Wartezeiten lang, und
    eine verspaetete Antwort zaehlt trotzdem.

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
  3. Strategie   EIN Befehl aus dem Start-Block (Standard:
                 "/w <eigener Name> nc +master fishing") plus "-mount" (s. 2.6)
                 und den beiden Abfragen. Auf die Antwort wird bis zu 25 s
                 gewartet (nach dem Einschalten; 20 s bei einem Bot, der schon
                 lief).
  4. Pruefung    Die Liste nach der Aenderung muss "master fishing" enthalten.
                 Wenn nicht: bis zu dreimal neu setzen, dann Abbruch mit
                 Meldung und der Bot wird wieder ausgeschaltet. Erst nach der
                 Pruefung steht im Chat "Auto-Angeln gestartet.". Zeigt der
                 Client die Antworten des Bots nie an, gilt der Start nach der
                 Wartezeit als "nicht bestaetigt" (mit Warnung) -- das AddOn
                 gibt dann nicht auf, kann aber auch nichts pruefen.

Beim Stoppen geht die Rueckname als EIN Befehl hinaus ("nc +mount,-master
fishing,?"), und derselbe Befehl wird alle drei Sekunden wiederholt, bis die
Liste ihn bestaetigt (hoechstens 24 s -- ein schlafender Bot braucht bis zu 17 s).
ERST DANN wird der Bot ausgeschaltet, und nur, wenn das AddOn ihn selbst
eingeschaltet hat. Wer den Selbstbot schon vorher an hatte (Botpad, AutoTravel,
Servereinstellung), behaelt ihn an. Auch waehrend einer AutoTravel-Reise, die
sich auf den Selbstbot verlaesst, bleibt er an. Hat jemand anderes den
Selbstbot waehrenddessen ausgeschaltet, wird er nicht wieder eingeschaltet.

Abmelden und /reload waehrend des Angelns: die Rueckname geht noch hinaus, den
Bot auszuschalten wird aber nicht im selben Atemzug versucht (der Server
verwirft dabei die noch wartende Anweisung). Stattdessen merkt sich das AddOn,
dass etwas aufzuraeumen ist ("AutoFishPending" in den gespeicherten Daten),
schaut nach dem naechsten Anmelden nach und raeumt dann auf.

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
  /fb auto diag      Fehlersuche: Zustand des Selbstbots, die Strategieliste
                     des Bots, Gruppe/Reittier/Botpad/AutoTravel und die
                     letzten gesendeten und empfangenen Zeilen (mit Zeitangabe)
  /fb auto probe     fragt den Bot nach seinen Strategien (Antwort in "diag")

  Tastenbelegung   "Auto-Angeln umschalten" und "Auto-Angeln-Panel
                   umschalten" stehen in den Tastaturbelegungen
                   unter "Fishing Buddy" bereit.

  Makro            /run FishingBuddy_ToggleAutoFishing()

Nach "Stopp" laeuft die Rueckname noch einige Sekunden (siehe oben); in dieser
Zeit meldet ein neuer Start "Der Bot wird noch gestoppt, einen Moment bitte." und tut nichts.

2.3 Die Befehle anpassen
------------------------
Unter "/fb auto edit" stehen frei editierbare Bloecke, ein Befehl pro Zeile.
Der Umschalter ".playerbots bot self" gehoert NICHT hinein: das AddOn schaltet
selbst und nur bei Bedarf. (Steht die Zeile noch in einem gespeicherten Block
der Fassung 0.9.9, wird sie beim Ausfuehren uebersprungen und das gemeldet.
Blocks, die noch genau dem alten Standard entsprechen, werden beim Laden durch
den neuen Standard ersetzt.)

  Beim Start        nach dem Einschalten gesendet
  Nachfassen        gesendet, wenn die Kontrolle die Strategie vermisst
  Beim Stoppen      vor dem Ausschalten gesendet
  Koeder auftragen  wird gesendet, wenn der Koeder ablaeuft

Voreingestellt sind:

  Start:       /w %p nc +master fishing
  Nachfassen:  /w %p nc +master fishing
  Stopp:       /w %p nc -master fishing
  Koeder:      /w %p u %l

Regeln fuer die Zeilen:

  /w %p nc ...  erreicht den eigenen Selbstbot. ALLE "nc"-Zeilen eines Blocks
                (auch mehrere, auch mit Kommalisten) fasst das AddOn zu einem
                einzigen Befehl zusammen, weil der Bot je Takt nur einen
                "nc"-Befehl behaelt. Die Reihenfolge bleibt erhalten.
  .befehl       geht als Server-Befehl raus (Punkt am Anfang)
  /w NAME text  Fluestern an jemand anderen
  /p text       Gruppenchat (ebenso /s /y /g /o /ra /rw /bg /1 ...).
                Ausnahme: "/p nc ..." geht immer an den eigenen Selbstbot.
                Eine andere /p-Zeile wird ohne Gruppe NICHT gesendet (der
                Server wuerde sie verwerfen) und das einmal gemeldet.
  /sonstiges    wird als normaler Slash-Befehl ausgefuehrt
  -- text       Kommentarzeile, wird uebersprungen

Platzhalter:  %p = eigener Charaktername, %z = Zone, %s = Unterzone

Die Fluesterzeilen an sich selbst (und die Antworten des Bots) blendet das AddOn
aus dem Chat aus ("Bot-Fluestern im Chat ausblenden", in den Optionen). Das
gilt fuer das normale Chatfenster; Addons, die Fluestern selbst mitschneiden,
und ein GM-Chatfenster zeigen sie weiter an, und ein "Abwesend"- oder
"Nicht stoeren"-Status antwortet unter Umstaenden auf das eigene Fluestern.

2.4 Die Ueberwachung
--------------------
Solange das Auto-Angeln laeuft, prueft das AddOn alle zwei Sekunden:

  * Angel noch angelegt?        sonst Stopp
  * Charakter tot?              sonst Stopp
  * Kampf begonnen?             Stopp (abschaltbar)
  * Taschen voll?               Stopp oder Warnung (einstellbar)
  * Zeitlimit erreicht?         Stopp (0 = kein Limit)
  * Koeder abgelaufen?          Bot-Befehl oder Warnung mit Ton
  * Selbstbot ausgeschaltet?    Stopp mit Meldung (jemand hat ihn abgeschaltet)
  * Im Sattel?                  Warnung (im Sattel kann nicht geangelt werden)
  * Laengere Zeit kein Fang?    Der Bot wird nach seiner Strategieliste
                                gefragt (Antwortzeit bis 20 s); fehlt "master
                                fishing", wird sie neu gesetzt. Verschwindet
                                sie dreimal (der Bot nimmt sie selbst zurueck,
                                wenn im Umkreis kein Wasser liegt), stoppt das
                                AddOn und sagt es. Waehrend einer AutoTravel-
                                Reise ruht die Kontrolle.

2.5 Koeder automatisch auftragen
--------------------------------
Es gibt drei Wege, den Koeder zu erneuern. Der erste ist vollautomatisch, die
anderen beiden brauchen einen Tastendruck beziehungsweise einen Klick.

(1) Ueber den Bot  --  Einstellung "Koeder vom Bot auftragen lassen"

    Faellt der Koeder unter 30 Sekunden Restlaufzeit, schickt das AddOn den
    Befehl aus dem Block "Koeder auftragen" an den Bot. Weil der Bot
    serverseitig laeuft, gelten fuer ihn die Client-Beschraenkungen nicht.

    Voreingestellt ist:   /w %p u %l

    Platzhalter in diesem Block:
        %l = Itemlink des Koeders
        %i = Item-ID
        %n = Name des Koeders

    Ob dein Playerbot-Build den "use"-Befehl kennt, muss sich zeigen. Auch
    waehrend der Bot angelt (er kanalisiert dann) kann das Benutzen eines
    Gegenstands scheitern -- dieser Weg gelingt deshalb moeglicherweise oft
    nicht. Das AddOn merkt es selbst: klappt es nach drei Versuchen nicht,
    gibt es auf, sagt Bescheid und faellt auf die manuellen Wege zurueck. Nach
    einem "/fb auto lure" (aus und wieder an) probiert es erneut.

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
(Standard an) steht "-mount" schon im allerersten Strategiebefehl, und beim
Stoppen kommt "+mount" zurueck -- aber nur, wenn die Strategie vorher in der
Liste des Bots stand. Kommt "mount" nach einem fremden "nc !" zurueck, nimmt die
naechste Kontrolle sie erneut heraus. Wer beim Start schon im Sattel sitzt,
bekommt einen Hinweis und das Auto-Angeln startet nicht.

2.7 Zusammenspiel mit Botpad und AutoTravel
-------------------------------------------
Botpad (bis 1.2) setzt bei JEDER Meldung "SelfBot is now active." seinen Modus
(nc !, co !, ...) und entfernte damit "master fishing" wieder; im Modus "Minimal"
nahm es ausserdem die Chat-Strategie weg, der Bot wurde taub fuer Chatbefehle.
Ab Botpad 1.3 bittet das AddOn Botpad per Botpad.Bot.Hold("Fishing Buddy") um
Zurueckhaltung, solange das Auto-Angeln laeuft (Release beim Stoppen). Bei einem
aelteren Botpad wartet das AddOn nach dem Einschalten 3,5 s, bis dessen Salve
vorbei ist, und warnt bei "Minimal" vor dem Problem (Botpad aktualisieren).
Schlaegt der Hold-Aufruf fehl, wird wie bei einem aelteren Botpad gewartet.
Kommt es trotzdem durcheinander: "/bp freigeben" in Botpad.

AutoTravel setzt zu Reisebeginn eigene Strategien (nc !) und bewegt den
Charakter. Waehrend einer Reise laesst das AddOn den Bot in Ruhe und startet
nicht; danach setzt die naechste Kontrolle die Strategie bei Bedarf neu. Ist
beides geladen, schaltet AutoTravel den Selbstbot fuer die Reise ein -- das
Auto-Angeln erkennt das (der Bot antwortet auf "nc ?") und schaltet nicht um.

2.8 Wenn nichts geangelt wird
-----------------------------
  1. Steht im Chat "Fishing Buddy ... loaded"? Wenn nicht, ist das AddOn nicht
     geladen: Ordnername (muss "FishingBuddy" sein), Version der TOC, und mit
     /console scriptErrors 1 nach Lua-Fehlern sehen.
  2. /fb auto diag  zeigt, was passiert ist:
       "self bot off" und eine Verweigerung im Verlauf -> der Server erlaubt den
         Selbstmodus nicht (AiPlayerbot.SelfBotLevel: 0 = aus, 1 = nur
         Spielleiter, 2 = alle, mehr = zusaetzlich beim Anmelden automatisch).
       Keine Strategieliste -> der Bot antwortet nicht. Spielleiter-Konten haben
         Fluestern aus, bis ".whispers on" eingegeben wurde. Hat jemand mit "-chat"
         die Chatbefehle abgeschaltet (oder Botpad bis 1.2 im Modus "Minimal"),
         hilft Aus- und wieder Einschalten; Botpad auf 1.3 bringen. Ein frisch
         eingeschalteter Bot antwortet erst nach etwa 10 Sekunden.
       "master fishing" fehlt in der Liste -> ein anderes AddOn oder ein
         gespeicherter Strategiesatz nimmt sie zurueck, oder der Bot beendet das
         Angeln selbst, weil im Umkreis (10 bis 30 Meter) kein angelbares Wasser
         liegt. Dann ein paar Meter ans Ufer treten.
  3. Steht "master fishing" in der Liste und es wird trotzdem nicht ausgeworfen,
     liegt es am Bot selbst (kein Wasser in Reichweite, Sichtlinie, Reittier,
     Kampf, Schwimmen) -- das sind Bedingungen im Server, nicht im AddOn.
  4. Der Server speichert die Strategien des Bots. Bleibt "master fishing" nach
     einem Absturz oder nach dem Ausschalten des Bots von aussen gespeichert,
     kommt sie beim naechsten Einschalten zurueck; "/w <Name> nc -master
     fishing" bei eingeschaltetem Selbstbot nimmt sie wieder heraus.

2.9 Grenzen
-----------
  * Alles oben ist gegen Quelltext und ein nachgebautes Modell geprueft, NICHT
    in einem echten Client gegen einen echten Server. Die Wartezeiten stammen
    aus dem Quelltext des Servers; "/fb auto diag" zeigt, wie es sich tatsaechlich
    verhaelt.
  * Hat jemand den Selbstbot von aussen ausgeschaltet, bevor die Rueckname
    ankam, kann "master fishing" in den gespeicherten Strategien des Bots
    stehenbleiben (s. 2.8, Punkt 4).
  * Das Koeder-Auftragen ueber den Bot gelingt waehrend des Angelns oft nicht
    (s. 2.5).


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
