Fishing Buddy 0.9.9-enhanced
============================
Erweiterte Fassung fuer WoW 3.3.5a (WotLK) / AzerothCore

Basis ist Fishing Buddy 0.9.8p1 von Sutorix. Ergaenzt wurden:
Bugfixes, ein Auto-Angeln-Modul fuer Playerbots und eine
Sitzungs-Statistik.


1. Installation
---------------
Den Ordner "FishingBuddy" nach

    <WoW-Verzeichnis>/Interface/AddOns/

kopieren (vorhandene Version vorher ersetzen). Danach WoW komplett
neu starten -- ein /reload reicht beim ersten Mal nicht, weil sich
die TOC-Datei geaendert hat.

Alte gespeicherte Daten (Fische, Fundorte, Outfits) bleiben
erhalten, es wird nichts geloescht.


2. Auto-Angeln ueber Playerbot
------------------------------

2.1 Wie es funktioniert
-----------------------
Der WoW-Client von 3.3.5a laesst es nicht zu, dass ein AddOn
selbstaendig Zauber wirkt -- die dafuer noetigen Funktionen sind
geschuetzt und brauchen einen echten Mausklick oder Tastendruck.
Ein AddOn kann also nicht von sich aus die Angel auswerfen.

Was ein AddOn aber darf: Chat- und Server-Befehle senden. Genau
darauf setzt dieses Modul auf. Es schickt die Playerbot-Befehle,
die den Bot das Angeln uebernehmen lassen, und uebernimmt danach
die Ueberwachung.

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

  Tastenbelegung   "Auto-Angeln umschalten" und "Auto-Angeln-Panel
                   umschalten" stehen in den Tastaturbelegungen
                   unter "Fishing Buddy" bereit.

  Makro            /run FishingBuddy_ToggleAutoFishing()

2.3 Die Befehle anpassen  --  WICHTIG
-------------------------------------
Playerbot-Builds unterscheiden sich in der Befehlssyntax. Deshalb
ist nichts fest verdrahtet: unter "/fb auto edit" stehen drei frei
editierbare Bloecke, ein Befehl pro Zeile.

  Beim Start        wird einmalig beim Einschalten gesendet
  Nachfassen        wird wiederholt, wenn laengere Zeit nichts
                    gefangen wurde (Stillstands-Erkennung)
  Beim Stoppen      wird beim Ausschalten gesendet
  Koeder auftragen  wird gesendet, wenn der Koeder ablaeuft

Voreingestellt sind:

  Start:       .playerbots bot self
               /p nc +master fishing

  Nachfassen:  /p nc +master fishing

  Stopp:       /p nc -master fishing
               .playerbots bot self

Beide Bloecke sind auf AzerothCore mit mod-playerbots getestet.

Wichtig zum Verstaendnis: ".playerbots bot self" ist ein
Umschalter -- derselbe Befehl schaltet den Self-Bot an und wieder
aus. Deshalb steht er im Start- und im Stopp-Block, aber bewusst
NICHT im Nachfass-Block. Wuerde er dort stehen, wuerde jedes
Nachfassen den Bot wieder abschalten statt ihn anzustossen.
Der Nachfass-Block setzt nur die Angel-Strategie neu.

Regeln fuer die Zeilen:

  .befehl      geht als Server-Befehl raus (Punkt am Anfang)
  /p text      geht als Chatnachricht in den Gruppenkanal
               (ebenso /s /y /g /o /ra /rw /bg /w /1 ...)
  /sonstiges   wird als normaler Slash-Befehl ausgefuehrt
  -- text      Kommentarzeile, wird uebersprungen

Platzhalter:  %p = eigener Charaktername
              %z = Zone
              %s = Unterzone

2.4 Der Watchdog
----------------
Solange das Auto-Angeln laeuft, prueft das AddOn alle zwei Sekunden:

  * Angel noch angelegt?        sonst Stopp
  * Charakter tot?              sonst Stopp
  * Kampf begonnen?             Stopp (abschaltbar)
  * Taschen voll?               Stopp oder Warnung (einstellbar)
  * Zeitlimit erreicht?         Stopp (0 = kein Limit)
  * Koeder abgelaufen?          Warnung mit Ton
  * laengere Zeit kein Fang?    Nachfass-Befehle erneut senden

Der letzte Punkt ist der wichtigste im Dauerbetrieb: wenn der Bot
aus irgendeinem Grund aus dem Angel-Modus faellt, wird er von
selbst wieder angestossen, ohne dass man daneben sitzen muss.

2.5 Koeder automatisch auftragen
--------------------------------
Es gibt drei Wege, den Koeder zu erneuern. Der erste ist
vollautomatisch, die anderen beiden brauchen einen Tastendruck
beziehungsweise einen Klick.

(1) Ueber den Bot  --  Einstellung "Koeder vom Bot auftragen lassen"

    Faellt der Koeder unter 30 Sekunden Restlaufzeit, schickt das
    AddOn den Befehl aus dem Block "Koeder auftragen" an den Bot.
    Weil der Bot serverseitig laeuft, gelten fuer ihn die
    Client-Beschraenkungen nicht -- das ist der einzige wirklich
    freihaendige Weg.

    Voreingestellt ist:   /p u %l

    Platzhalter in diesem Block:
        %l = Itemlink des Koeders
        %i = Item-ID
        %n = Name des Koeders

    Ob dein Playerbot-Build den "use"-Befehl kennt, muss sich
    zeigen. Das AddOn merkt es selbst: klappt es nach drei
    Versuchen nicht, gibt es auf, sagt Bescheid und faellt auf die
    manuellen Wege zurueck. Nach einem "/fb auto lure" (aus und
    wieder an) probiert es erneut.

    Falls dein Server eine andere Syntax braucht, aendere die
    Zeile einfach unter "/fb auto edit".

(2) Per Taste

    In den Tastaturbelegungen gibt es unter "Fishing Buddy" den
    Eintrag "Besten Koeder auftragen". Ein Druck auf die Taste
    traegt den Koeder auf -- ohne Maus, ohne Fenster.

    Technischer Hintergrund: das AddOn liest die belegte Taste aus
    und legt sie per SetOverrideBindingClick direkt auf den
    sicheren Button. Nur so laesst WoW eine geschuetzte Aktion per
    Tastendruck zu.

(3) Per Klick

    Rechts im Panel sitzt der Koeder-Knopf. Wird ein Koeder
    faellig, faengt er gruen an zu pulsieren. Der Tooltip zeigt,
    welcher Koeder genommen wird, wieviel Bonus er bringt und
    welche Taste belegt ist. Ist nichts Passendes in den Taschen,
    ist der Knopf ausgegraut.

Warum nicht einfach immer automatisch? Der WoW-Client von 3.3.5a
laesst die Benutzung von Gegenstaenden nur als Reaktion auf einen
echten Tastendruck oder Mausklick zu. Ein AddOn, das den Koeder
von sich aus aus dem Nichts auftraegt, ist technisch nicht
moeglich -- deshalb der Umweg ueber den Bot.


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
