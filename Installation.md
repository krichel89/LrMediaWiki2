# Installation

LrMediaWiki2 ist ein Zusatzmodul für Adobe Lightroom Classic. Es lädt Fotos nach
Wikimedia Commons und pflegt dabei strukturierte Daten (SDC).

## Voraussetzungen

- Adobe Lightroom Classic 6 oder neuer. Lightroom CC, die Cloud-Fassung, kann
  keine Zusatzmodule laden.
- Ein Benutzerkonto auf Wikimedia Commons.
- Windows 10 oder neuer, oder macOS 11 oder neuer.

## Schritt 1: Paket herunterladen

Auf der Releases-Seite des Projekts liegen zwei Dateien. Für die Installation
wird nur die erste gebraucht:

- `LrMediaWiki2-<Version>.zip` — das Zusatzmodul. Diese Datei nehmen.
- `LrMediaWiki2-complete-<Version>.zip` — zusätzlich der Quelltext der
  Hintergrund-App, die Editorseite und die Bauskripte. Nur für die
  Weiterentwicklung interessant.

## Schritt 2: Entpacken

Das Archiv entpacken. Darin liegt genau ein Ordner:

```
mediawiki.lrdevplugin
```

Diesen Ordner an eine Stelle legen, an der er dauerhaft bleiben kann — nicht in
einen Download-Ordner, der regelmäßig geleert wird. Bewährt haben sich:

- Windows: `C:\Users\<Name>\Documents\Lightroom Plugins\`
- macOS: `~/Library/Application Support/Adobe/Lightroom/Modules/`

Lightroom merkt sich den Pfad. Wird der Ordner später verschoben, meldet der
Zusatzmodul-Manager das Modul als fehlend.

## Schritt 3: In Lightroom einbinden

1. Lightroom Classic starten.
2. Menü Datei, Eintrag Zusatzmodul-Manager.
3. Unten links auf Hinzufügen klicken.
4. Den Ordner `mediawiki.lrdevplugin` auswählen und bestätigen.

In der Liste steht danach LrMediaWiki2 mit einem grünen Punkt. Erscheint eine
Fehlermeldung, hilft meistens ein Neustart von Lightroom.

## Schritt 4: Anmelden

Die Anmeldung läuft über OAuth im Browser. Ein Bot-Passwort wird nicht mehr
gebraucht.

1. Im Zusatzmodul-Manager LrMediaWiki2 auswählen.
2. Im Abschnitt Anmeldung auf Anmelden klicken.
3. Der Standardbrowser öffnet die Wikimedia-Seite. Dort anmelden und den Zugriff
   bestätigen.
4. Der Browser leitet auf eine lokale Adresse weiter, und Lightroom meldet die
   erfolgreiche Anmeldung.

Der Zugriffsschlüssel liegt danach im Schlüsselbund des Betriebssystems, nicht in
den Voreinstellungen und nicht in Export-Vorgaben. Er wird selbsttätig erneuert.

## Schritt 5: Metadatenfelder einblenden

Damit die Felder des Zusatzmoduls in der Bibliothek sichtbar werden:

1. In den Modus Bibliothek wechseln.
2. Rechts im Metadatenbereich oben auf das Auswahlfeld klicken.
3. Einen der LrMediaWiki-Einträge wählen.

## Erster Upload

1. In der Bibliothek ein Foto auswählen.
2. Im Metadatenbereich Beschreibung, Kategorien und die übrigen Felder
   ausfüllen.
3. Menü Datei, Eintrag Exportieren.
4. Oben bei Exportieren nach den Eintrag MediaWiki wählen.
5. Die Angaben prüfen und auf Exportieren klicken.

Das Zusatzmodul hängt an jeden Upload die Wartungskategorie
`Uploaded with LrMediaWiki2` an. Sie dient dazu, die eigenen Uploads später
wiederzufinden.

## Die Hintergrund-App ist optional

Der Editor für strukturierte Daten läuft im Browser. Er arbeitet in zwei
Betriebsarten, und die einfachere braucht keine Einrichtung.

**Ohne Hintergrund-App.** Der Editor öffnet sich als lokale Seite. Beim
Speichern legt er eine kleine Datei im Download-Ordner ab, die Lightroom
selbsttätig einliest und danach löscht. Das funktioniert sofort nach der
Installation, ohne dass etwas eingeschaltet werden muss.

**Mit Hintergrund-App.** Dann bleibt die Editorseite offen und zieht beim
Fotowechsel in Lightroom mit, und Speichern schreibt unmittelbar in den Katalog.
Einschalten unter Bibliothek oder Datei, Zusatzmoduloptionen, Eintrag
Hintergrund-App (SDC-Brücke).

Wer die Hintergrund-App nicht braucht, kann diesen Abschnitt überspringen. Am
Funktionsumfang des Zusatzmoduls ändert sie nichts.

### Was die Hintergrund-App tut

Sie ist ein kleines Programm, das ausschließlich auf der lokalen Schleife
(127.0.0.1) lauscht, auf einem vom Betriebssystem zugewiesenen Port. Jede
Anfrage muss ein Sitzungstoken mitbringen, das bei jedem Start neu erzeugt wird.
Sie nimmt keine Verbindungen von außen an und beendet sich selbst, wenn drei
Minuten lang kein Lebenszeichen aus Lightroom kommt.

### Erster Start unter macOS

Die mitgelieferten Programme sind nicht von Apple beglaubigt, sofern das Release
nicht ausdrücklich anderes angibt. Beim ersten Start meldet macOS deshalb, das
Programm könne nicht geprüft werden. Zwei Wege:

- Systemeinstellungen, Datenschutz und Sicherheit. Dort steht der Hinweis auf das
  blockierte Programm mit einer Schaltfläche Dennoch erlauben.
- Oder einmal im Terminal, wobei `<Pfad>` der Ordner `mediawiki.lrdevplugin`
  ist:

  ```
  xattr -dr com.apple.quarantine "<Pfad>/bin"
  ```

Danach startet die Hintergrund-App ohne weitere Rückfrage.

### Erster Start unter Windows

Windows Defender SmartScreen kann eine Warnung zeigen. Das Programm wird von
Lightroom gestartet und nicht doppelt angeklickt, deshalb tritt das selten auf.
Erscheint die Warnung, über Weitere Informationen und Trotzdem ausführen
zulassen.

## Fehlersuche

**Das Zusatzmodul erscheint nicht im Zusatzmodul-Manager.** Wurde der Ordner
`mediawiki.lrdevplugin` selbst ausgewählt, oder nur sein übergeordneter Ordner?
Lightroom braucht den Ordner mit der Endung.

**Die Anmeldung bricht ab.** Die Rückleitung geht auf `127.0.0.1`, Port 8128.
Blockiert eine Firewall oder ein Sicherheitsprogramm die lokale Schleife, kommt
die Antwort nicht an. Ist der Port von einem anderen Programm belegt, schlägt die
Anmeldung ebenfalls fehl.

**Die Hintergrund-App startet nicht.** Zustand und letzte Fehlermeldung stehen im
Dialog unter Zusatzmoduloptionen, Eintrag Hintergrund-App (SDC-Brücke). Dort
steht auch der Pfad zum Protokoll der App. Der Editor funktioniert weiterhin über
die Datei-Betriebsart.

**Eine offene Editorseite reagiert nicht mehr.** Sie zeigt das selbst an: oben
steht der Verbindungszustand, und bei einem Abbruch erscheint ein Hinweisbalken.
Nach einem Neustart von Lightroom läuft die Hintergrund-App auf einem neuen Port;
eine vorher geöffnete Seite ist dann nicht mehr gültig und sollte geschlossen
werden. Den Editor in Lightroom neu öffnen.

**Ausführliche Protokolle.** Im Zusatzmodul-Manager lässt sich die
Protokollierung einschalten. Danach schreibt das Zusatzmodul mit, was es tut.

## Deinstallation

1. Zusatzmodul-Manager öffnen, LrMediaWiki2 auswählen, auf Entfernen klicken.
2. Den Ordner `mediawiki.lrdevplugin` löschen.
3. Der Zugriffsschlüssel bleibt im Schlüsselbund des Betriebssystems und kann
   dort von Hand entfernt werden. Unter Einträgen mit LrMediaWiki suchen.

Die in den Fotos gespeicherten Angaben bleiben im Lightroom-Katalog erhalten.
Wird das Zusatzmodul später wieder eingebunden, sind sie noch vorhanden.
