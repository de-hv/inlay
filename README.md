# Inlay

Gestor de ventanas en mosaico (*tiling*) para macOS, escrito en Swift. El objetivo es reunir en una sola app
nativa tres cosas que hoy son tres programas: el gestor de ventanas, los bordes de la ventana activa y una barra
de menús con los *workspaces*, todo con un único fichero de configuración (`inlay.toml`).

Se compila e instala **solo con las Command Line Tools de Xcode**: sin Xcode, sin cuenta de Apple.

## Estado del proyecto

En desarrollo. Inlay es un *fork* de [AeroSpace](https://github.com/nikitabobko/AeroSpace) que se compila sin
Xcode, con su propia forma de colocar las ventanas nuevas (*dwindle*) y sin el layout *accordion*.

| Parte | Estado |
|---|---|
| Gestor de ventanas (árbol, workspaces, comandos, CLI) | Funciona como AeroSpace `74a1bf1`, con otro nombre |
| Build, instalación y desinstalación sin Xcode | Hecho |
| Auto-tiling tipo *dwindle*, sin layout *accordion* | Hecho (ver [Mosaico](#mosaico)) |
| Barra de menús con *chips* de workspaces, temas y ventana de Ajustes | Hecho (ver [Barra de menús y Ajustes](#barra-de-menús-y-ajustes)) |
| Bordes de ventana | Hecho, con API pública (ver [Bordes de ventana](#bordes-de-ventana)) |
| Tests | Suite de Swift Testing (`scripts/test.sh`) para el árbol, la configuración, los comandos del árbol, la barra de menús, los bordes y el editor de la config. El resto de la suite original (XCTest) está por migrar |

El formato de configuración y los comandos son los de AeroSpace con las diferencias de [Mosaico](#mosaico): su
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

### Mosaico

Una ventana nueva **divide en dos la ventana enfocada**, como el layout *dwindle* de Hyprland: si la enfocada es
más ancha que alta quedan lado a lado; si no, apiladas. La nueva va a la derecha o debajo. Al cerrar una ventana,
su vecina recupera el espacio.

```toml
[tiling]
    new-window-placement = 'dwindle'   # o 'after-focused': el comportamiento de AeroSpace
    split-ratio = 0.5                  # 0.1 – 0.9: fracción que conserva la ventana que se divide
```

Inlay **no tiene layout *accordion***. Para poder usar tal cual un `aerospace.toml`, sus formas se aceptan con
un aviso (no con un error) y se tratan como `tiles`:

| En el `aerospace.toml` | En Inlay |
|---|---|
| `default-root-container-layout = 'accordion'` | Se usa `'tiles'` |
| `accordion-padding = 30` | Se ignora |
| `layout accordion`, `layout h_accordion`, `layout v_accordion` | `layout tiles`, `layout h_tiles`, `layout v_tiles` |
| `layout tiles accordion` (alternar) | `layout tiles` |

Los avisos salen en `inlay reload-config` y en el menú de la barra («Config contains warnings...»).

## Barra de menús y Ajustes

El item de la barra muestra **todos los workspaces** y marca el enfocado (no distingue monitores). Se configura
en la tabla `[menu-bar]` de la config; está documentada en
[`docs/config-examples/default-config.toml`](docs/config-examples/default-config.toml).

| Clave | Valores | Por defecto |
|---|---|---|
| `enabled` | `true`, `false` | `true` |
| `theme` | `'chips'`, `'chips-icons'`, `'square'`, `'minimal'` | `'chips'` |
| `show-app-icons` | `true`, `false` | lo decide el tema (`true` en `chips-icons`) |
| `dim-empty-workspaces` | `true`, `false` | `true` |
| `show-mode` | `true`, `false` | `false` |
| `[menu-bar.colors]` `accent` | color | `'system-accent'` |
| `[menu-bar.colors]` `focused`, `occupied`, `empty` | color o `'auto'` | `'auto'` |

Un color es `'#RRGGBB'`, `'#RRGGBBAA'` o `'system-accent'`. `'auto'` es el color del texto de la barra (blanco
en barra oscura, negro en clara). Con todo en `'auto'` y sin iconos, el item es una imagen plantilla idéntica
a la de Aeromenu; un color fijo no se adapta a la barra.

- **Clic** en un workspace: va a él. **Clic en el enfocado** o **clic derecho**: abre el menú (workspaces,
  ventana enfocada, layout, modo, config, pausar y Ajustes).
- **Ajustes…** (⌘, en el menú, o abrir Inlay otra vez desde Aplicaciones) edita esas claves **en tu fichero de
  config**, línea a línea y sin tocar comentarios ni el resto del fichero, y recarga la config. Si la config es
  un enlace simbólico, se escribe en su destino. Si aún no tienes config, el primer cambio crea
  `~/.config/inlay/inlay.toml` a partir de la incluida. Una clave escrita con puntos (`menu-bar.theme = …`) o
  dentro de una tabla en línea no se edita desde Ajustes: su control aparece desactivado.

## Bordes de ventana

Inlay dibuja un borde de color alrededor de cada ventana gestionada (en mosaico o flotante) de los workspaces
visibles. El color sale del estado que el gestor ya conoce, sin heurísticas de foco. Se configura en la tabla
`[borders]`, documentada en [`docs/config-examples/default-config.toml`](docs/config-examples/default-config.toml),
o en la pestaña **Borders** de Ajustes.

| Clave | Valores | Por defecto |
|---|---|---|
| `enabled` | `true`, `false` | `true` |
| `width` | 1 … 20 (puntos) | `4` |
| `corner-radius` | 0 … 40 (puntos) | `16` |
| `active-color` | color | `'system-accent'` |
| `inactive-color` | color | `'#8E8E9373'` |
| `floating-color` | color | `'#BF5AF2'` |
| `[borders.mode-colors]` `<modo>` | color | tabla vacía |

- **Color de la ventana enfocada**: el del modo de atajos activo si tiene entrada en `[borders.mode-colors]`; si
  no, `floating-color` si es flotante; si no, `active-color`. Las demás ventanas usan `inactive-color`.
- Un color **totalmente transparente** (`'#00000000'`) significa «sin borde»: con
  `inactive-color = '#00000000'` solo lleva borde la ventana activa.
- **Sin borde**: ventanas en pantalla completa (la de Inlay y la nativa de macOS), minimizadas, de apps ocultas,
  diálogos y popups, las de workspaces no visibles, y la ventana que estás arrastrando o redimensionando con el
  ratón (el borde vuelve al soltar).
- El borde va **por fuera** del marco de la ventana, en el hueco entre ventanas: no tapa contenido y no recibe
  clics. Conviene que los `gaps` sean al menos el doble de `width` (la config incluida usa 14 con el borde de 4);
  con gaps más pequeños los bordes de dos ventanas vecinas se tocan o se solapan.
- El radio de las esquinas es fijo: macOS no deja leer el de las ventanas de otras apps. Ajústalo a ojo.
- Los bordes desaparecen al pausar Inlay (`inlay enable off`), al salir y con `enabled = false`.
- `[borders.mode-colors]` todavía no se edita desde Ajustes: escríbela en el fichero.

Cada borde es una ventana propia de Inlay, transparente, colocada justo encima de su ventana en el orden de
apilado, así que una ventana flotante de otra app tapa los bordes de las ventanas que tiene detrás. Todo con
API pública de AppKit; no hay código de JankyBorders ni se usa SkyLight.

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
scripts/test.sh         # ejecuta los tests (acepta los argumentos de 'swift test', p. ej. --filter DwindleTest)
scripts/make-icon.sh    # regenera Support/AppIcon.icns a partir de scripts/icon/AppIcon.swift
```

Para ver el item de la barra sin arrancar Inlay, `--render-menu-bar` lo dibuja fuera de pantalla (cada tema, en
barra oscura y clara, con colores por defecto y personalizados; `_sheet.png` los reúne todos) y termina:

```sh
build/Inlay.app/Contents/MacOS/Inlay --render-menu-bar /tmp/inlay-item
INLAY_RENDER_DIR=/tmp/inlay-item scripts/test.sh --filter SettingsModelTest   # las pestañas de Ajustes, a PNG
```

Lo mismo para los bordes. `--render-borders` los dibuja fuera de pantalla en cada estado, y `--debug-borders`
los muestra de verdad unos segundos alrededor de las ventanas que haya en pantalla (sin mover nada y sin permiso
de Accesibilidad), imprime cómo han quedado apilados y los quita:

```sh
build/Inlay.app/Contents/MacOS/Inlay --render-borders /tmp/inlay-borders
build/Inlay.app/Contents/MacOS/Inlay --debug-borders 5
```

Los scripts fuerzan `DEVELOPER_DIR=/Library/Developer/CommandLineTools` aunque `xcode-select` apunte a Xcode,
para garantizar que el proyecto no depende de él. Para compilar a mano:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift test
```

Los tests usan Swift Testing (XCTest no viene en las Command Line Tools). Todas las suites van anidadas en
`InlayTests` (`extension InlayTests { @Suite @MainActor struct FooTest { ... } }`), que es `.serialized`: los tests
comparten el modelo global y no pueden ejecutarse en paralelo.

| Ruta | Contenido |
|---|---|
| `Sources/InlayApp` | Punto de entrada de la app (producto `InlayApp`, que en el bundle es `Contents/MacOS/Inlay`) |
| `Sources/AppBundle` | El gestor de ventanas: árbol, comandos, configuración, servidor, interfaz |
| `Sources/Cli` | La CLI `inlay` (cliente del socket `/tmp/com.davidhiguita.inlay-$USER.sock`) |
| `Sources/Common` | Código compartido por la app y la CLI |
| `Sources/BuildInfo` | Versión y hash de git, que `build-app.sh` pasa por variables de entorno |
| `Sources/PrivateApi` | Cabecera de `_AXUIElementGetWindow` |
| `Tests/InlayTests` | Tests con Swift Testing. En `support/` están las ventanas falsas y demás utilidades |
| `Sources/AppBundleTests` | Tests XCTest heredados que faltan por migrar (no se compilan por defecto: `INLAY_XCTEST=1`, requiere Xcode) |
| `Support` | `Info.plist` e icono del bundle |
| `scripts` | Build, tests, instalación, desinstalación e icono |
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
