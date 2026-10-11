# Inlay

Gestor de ventanas en mosaico (*tiling*) para macOS, escrito en Swift. El objetivo es reunir en una sola app
nativa tres cosas que hoy son tres programas: el gestor de ventanas, los bordes de la ventana activa y una barra
de menús con los *workspaces*, todo con un único fichero de configuración (`inlay.toml`).

Se compila e instala **solo con las Command Line Tools de Xcode**: sin Xcode, sin cuenta de Apple.

## Estado del proyecto

En desarrollo. Esta es la fase de **fundaciones**: Inlay es, por ahora, un *fork* renombrado de
[AeroSpace](https://github.com/nikitabobko/AeroSpace) que se compila sin Xcode.

| Parte | Estado |
|---|---|
| Gestor de ventanas (árbol, workspaces, comandos, CLI) | Funciona como AeroSpace `74a1bf1`, con otro nombre |
| Build, instalación y desinstalación sin Xcode | Hecho |
| Auto-tiling tipo *dwindle*, sin layout *accordion* | Pendiente |
| Barra de menús con *chips* de workspaces, temas y ajustes | Pendiente (hoy: el icono de menú de AeroSpace) |
| Bordes de ventana | Pendiente |
| Tests | La suite original usa XCTest, que no viene en las Command Line Tools; se migrará a Swift Testing |

El formato de configuración y los comandos son, de momento, los de AeroSpace: su
[guía](https://nikitabobko.github.io/AeroSpace/guide) y su
[lista de comandos](https://nikitabobko.github.io/AeroSpace/commands) sirven cambiando `aerospace` por `inlay`.
Hay una copia de esa documentación en [`docs/upstream-aerospace`](./docs/upstream-aerospace).

## Requisitos

- macOS 14 o posterior (probado en macOS 27, Apple Silicon).
- Command Line Tools de Xcode con Swift 6.2 o posterior: `xcode-select --install`.
- Conexión a internet la primera vez que se compila (SwiftPM descarga cuatro dependencias de GitHub).

## Instalación

```sh
git clone <este repo> inlay && cd inlay
./install.sh
```

`install.sh` compila, instala `Inlay.app` en `/Applications` (o en `~/Applications` si no hay permisos), enlaza
la CLI `inlay` en `~/.local/bin`, `/opt/homebrew/bin` o `/usr/local/bin`, crea `~/.config/inlay/inlay.toml` si
aún no tienes configuración y abre la app. Se puede ejecutar las veces que haga falta: actualiza lo instalado.

| Opción | Efecto |
|---|---|
| `--no-open` | No abre Inlay al terminar |
| `--stable-signing` | Firma con una identidad autofirmada local (ver más abajo) |
| `--adhoc-signing` | Firma ad hoc aunque esa identidad exista |
| `--import-aerospace` | Si no tienes configuración de Inlay, parte de tu `~/.aerospace.toml` en vez de la de por defecto |
| `INSTALL_DIR=…` | Carpeta donde instalar la app |
| `INLAY_BIN_DIR=…` | Carpeta donde enlazar la CLI |

Tu configuración **nunca se sobrescribe ni se borra** al instalar.

### Antes de abrir Inlay

- **Cierra AeroSpace, AeroMenu y `borders` (JankyBorders).** Hacen el mismo trabajo y dos gestores de ventanas a
  la vez se pelean por las ventanas. `install.sh` no los cierra: si detecta alguno, avisa y deja Inlay sin abrir.
  Inlay puede estar *instalado* junto a AeroSpace sin problema: no comparten configuración, socket, preferencias
  ni identificador.
- **Permiso de Accesibilidad.** Inlay mueve las ventanas con la API de Accesibilidad. La primera vez macOS pide el
  permiso: actívalo en *Ajustes del Sistema › Privacidad y seguridad › Accesibilidad*.

### Firma estable (`--stable-signing`)

macOS asocia el permiso de Accesibilidad a la firma de la app. Con la firma ad hoc por defecto, el permiso se
pierde **cada vez que se recompila** y hay que volver a darlo. `./install.sh --stable-signing` crea, una sola
vez, una identidad de firma autofirmada («Inlay Local Code Signing») en tu llavero de inicio de sesión y firma
con ella, de modo que el permiso se conserva entre compilaciones. macOS puede pedir la contraseña del llavero la
primera vez que `codesign` usa la clave: elige «Permitir siempre». Si algo falla, se firma ad hoc y se avisa.
Una vez creada la identidad, las siguientes instalaciones la usan sin tener que repetir la opción.

### Configuración

Inlay lee `~/.config/inlay/inlay.toml` (o `$XDG_CONFIG_HOME/inlay/inlay.toml`) o bien `~/.inlay.toml`; si
existen los dos, avisa de la ambigüedad y no carga ninguno. La configuración por defecto está en
[`docs/config-examples/default-config.toml`](./docs/config-examples/default-config.toml).

Los programas que Inlay lanza reciben las variables `INLAY_WINDOW_ID`, `INLAY_WORKSPACE`,
`INLAY_FOCUSED_WORKSPACE` e `INLAY_PREV_WORKSPACE` (y también con el nombre `AEROSPACE_*`, para que los scripts
escritos para AeroSpace sigan funcionando).

## Desinstalación

```sh
./uninstall.sh           # quita la app, el enlace de la CLI y el ítem de inicio
./uninstall.sh --purge   # además borra tu configuración y las preferencias de la app
```

No se eliminan la entrada de Accesibilidad (`tccutil reset Accessibility com.davidhiguita.inlay`) ni la
identidad de firma (bórrala en *Acceso a Llaveros* si quieres).

## Desarrollo

```sh
scripts/build-app.sh    # compila y deja build/Inlay.app firmada (no instala nada)
scripts/make-icon.sh    # regenera Support/AppIcon.icns a partir de scripts/icon/AppIcon.swift
```

Los scripts fuerzan `DEVELOPER_DIR=/Library/Developer/CommandLineTools` aunque `xcode-select` apunte a Xcode,
para garantizar que el proyecto no depende de él. Para compilar a mano:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build
```

| Ruta | Contenido |
|---|---|
| `Sources/InlayApp` | Punto de entrada de la app (producto `InlayApp`, que en el bundle es `Contents/MacOS/Inlay`) |
| `Sources/AppBundle` | El gestor de ventanas: árbol, comandos, configuración, servidor, interfaz |
| `Sources/Cli` | La CLI `inlay` (cliente del socket `/tmp/com.davidhiguita.inlay-$USER.sock`) |
| `Sources/Common` | Código compartido por la app y la CLI |
| `Sources/BuildInfo` | Versión y hash de git, que `build-app.sh` pasa por variables de entorno |
| `Sources/PrivateApi` | Cabecera de `_AXUIElementGetWindow` |
| `Sources/AppBundleTests` | Tests XCTest heredados (no se compilan por defecto: `INLAY_XCTEST=1`, requiere Xcode) |
| `Support` | `Info.plist` e icono del bundle |
| `scripts` | Build, instalación, desinstalación e icono |
| `axDumps` | Volcados de Accesibilidad de apps reales que usan los tests |

Cosas a tener en cuenta:

- **No uses `@State` de SwiftUI** (ni `#Preview`): en el SDK de macOS 27 son macros cuyo *plugin* solo viene con
  Xcode. Usa `@StateObject`/`ObservableObject`, `@Observable` + `@Bindable`, o AppKit.
- La versión está en el fichero [`VERSION`](./VERSION).

## Atribución y licencia

Inlay se distribuye bajo licencia MIT ([LICENSE](./LICENSE)).

- Deriva de **[AeroSpace](https://github.com/nikitabobko/AeroSpace)** de Nikita Bobko (MIT), commit `74a1bf1`:
  el gestor de ventanas, el formato de configuración, los comandos y la CLI vienen de ahí. Se conserva su aviso
  de copyright. Inlay no está afiliado al proyecto AeroSpace: por favor, no informes allí de fallos de Inlay.
- El build sin Xcode y los scripts de instalación siguen los de **Aeromenu**, del mismo autor que Inlay.
- **No** contiene código de JankyBorders (GPL-3.0).

El detalle, con las dependencias incluidas y sus licencias, está en [NOTICE.md](./NOTICE.md).
