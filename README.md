# Inlay

Gestor de ventanas en mosaico (*tiling*) para macOS, escrito en Swift. El objetivo es reunir en una sola app
nativa tres cosas que hoy son tres programas: el gestor de ventanas, los bordes de la ventana activa y una barra
de menús con los *workspaces*, todo con un único fichero de configuración (`inlay.toml`).

Se compila e instala **solo con las Command Line Tools de Xcode**: sin Xcode, sin cuenta de Apple.

## Estado del proyecto

**Versión 0.1.0, en su primera ronda de uso real.** Inlay es un *fork* de
[AeroSpace](https://github.com/nikitabobko/AeroSpace) que se compila sin Xcode, con su propia forma de colocar
las ventanas nuevas (*dwindle*), sin el layout *accordion*, con una barra de menús propia y con bordes de ventana.

| Parte | Estado | Cómo está comprobado |
|---|---|---|
| Build, instalación y desinstalación sin Xcode | Hecho | Build limpio desde cero con las Command Line Tools; `install.sh` y `uninstall.sh` ejecutados enteros en un entorno aislado (otro `HOME`, otra carpeta de instalación) |
| Gestor de ventanas (árbol, workspaces, comandos, CLI) | El de AeroSpace `74a1bf1`, con otro nombre | Tests (ventanas simuladas) |
| Auto-tiling tipo *dwindle*, sin layout *accordion* | Hecho (ver [Mosaico](#mosaico)) | Tests (ventanas simuladas), incluida una sesión pseudoaleatoria de 600 pasos |
| Barra de menús con *chips*, temas y ventana de Ajustes | Hecho (ver [Barra de menús y Ajustes](#barra-de-menús-y-ajustes)) | Tests e imágenes renderizadas |
| Bordes de ventana | Hecho, con API pública (ver [Bordes de ventana](#bordes-de-ventana)) | Tests, imágenes renderizadas y `--debug-borders` sobre ventanas reales |
| Tests | 588 tests de Swift Testing (`scripts/test.sh`): toda la suite original de AeroSpace migrada, más los de Inlay | Pasan con las Command Line Tools |

La columna «Cómo está comprobado» dice lo que se ha verificado de forma automática. Además, Inlay ya se ha
instalado y usado con el permiso de Accesibilidad (primera prueba, 2026-10-11). De esa prueba salieron los
cambios de esta revisión, que **aún no se han probado en uso real**, solo con tests e imágenes renderizadas:
firma estable por defecto, reparto en rejilla al arrancar (`startup-layout`), recuperar el sitio al volver de
minimizar o de pantalla completa nativa, *glow* opcional en el borde, item de la barra solo informativo y
colores por modo en Ajustes.

Limitaciones conocidas de esta versión:

- Los bordes se colocan con una API pública que no los ata a su ventana: entre que una ventana cambia y llega
  el siguiente refresco, su borde puede quedar un instante desfasado o por debajo de otra ventana.
- Solo Apple Silicon (el binario es `arm64`) y una sola pantalla probada.
- La interfaz (menú, Ajustes, mensajes) está en inglés.

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
| `--adhoc-signing` | Firma ad hoc en vez de con la identidad local (ver [Firma](#firma)) |
| `--import-aerospace` | Si no tienes configuración de Inlay, parte de tu `~/.aerospace.toml` en vez de la de por defecto |
| `INSTALL_DIR=…` | Carpeta donde instalar la app |
| `INLAY_BIN_DIR=…` | Carpeta donde enlazar la CLI |

Tu configuración **nunca se sobrescribe ni se borra** al instalar.

Con `--import-aerospace` se copia tu `aerospace.toml` tal cual (si es un enlace simbólico, se copia el fichero
al que apunta y el original no se toca). Revisa tres cosas en la copia: `start-at-login = true` haría que Inlay
se añadiese a los ítems de inicio la primera vez que arranca; los atajos o scripts que llaman a la CLI
`aerospace` siguen hablando con AeroSpace y deben llamar a `inlay`; y con `gaps` de 8 o menos los bordes de
dos ventanas vecinas se tocan (la config incluida usa 14).

### Antes de abrir Inlay

- **Cierra AeroSpace, AeroMenu y `borders` (JankyBorders).** Hacen el mismo trabajo y dos gestores de ventanas a
  la vez se pelean por las ventanas. `install.sh` no los cierra: si detecta alguno, avisa y deja Inlay sin abrir.
  Inlay puede estar *instalado* junto a AeroSpace sin problema: no comparten configuración, socket, preferencias
  ni identificador.
- **Permiso de Accesibilidad.** Inlay mueve las ventanas con la API de Accesibilidad. La primera vez macOS pide el
  permiso: actívalo en *Ajustes del Sistema › Privacidad y seguridad › Accesibilidad* (hace falta ser
  administrador; en un equipo gestionado esa lista puede estar bloqueada). Mientras no lo tenga, Inlay no hace
  nada: su item de la barra muestra un triángulo de aviso y la CLI responde «Can't connect to Inlay server».
  Si Inlay aparece activado en la lista pero sigue pidiéndolo (pasa tras recompilar con firma ad hoc), quítalo
  de la lista con el botón «−» y vuelve a abrir Inlay.

### Firma

macOS asocia el permiso de Accesibilidad a la firma de la app. Por eso `install.sh` firma **por defecto con una
identidad estable**: crea, una sola vez, una identidad autofirmada («Inlay Local Code Signing») en tu llavero de
inicio de sesión y firma con ella, de modo que el permiso se conserva entre compilaciones. macOS puede pedir la
contraseña del llavero la primera vez que `codesign` usa la clave: elige «Permitir siempre». Si la identidad no
se puede crear o usar, se firma ad hoc y se avisa.

Con `--adhoc-signing` no se usa la identidad: la firma ad hoc sirve para ejecutar Inlay en este Mac, pero el
permiso se pierde **cada vez que se recompila** y hay que volver a darlo. (`--stable-signing` se sigue
aceptando: ahora es lo que se hace por defecto.)

`scripts/build-app.sh` firma con esa identidad si ya existe (nunca la crea) y ad hoc si no;
`scripts/build-app.sh --sign-identity -` fuerza la firma ad hoc.

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
    startup-layout = 'grid'            # 'grid' | 'row' | 'dwindle': las ventanas que ya estaban abiertas
```

Las ventanas que **ya están abiertas cuando Inlay arranca** (o cuando se reanuda con `inlay enable on`) no se
colocan una a una: se reparten, workspace por workspace, según `startup-layout`.

| `startup-layout` | Resultado |
|---|---|
| `'grid'` (por defecto) | Rejilla equilibrada: `ceil(√n)` columnas y las filas que hagan falta, todas las filas con la misma altura. La última fila reparte su ancho entre las ventanas que tenga: 5 ventanas son 3 arriba y 2 abajo; 3 son 2 arriba y 1 abajo |
| `'row'` | Una sola fila con todas las ventanas al mismo ancho |
| `'dwindle'` | Sin reparto: cada ventana entra como una ventana nueva, una detrás de otra (con `new-window-placement = 'dwindle'`, una espiral con las últimas muy pequeñas) |

Solo afecta a ese momento. Las ventanas que abras después siguen `new-window-placement`, y la rejilla es un
árbol normal: se puede mover, redimensionar y reorganizar con los comandos de siempre. Al reanudar tras una
pausa solo se recolocan los workspaces en los que apareció alguna ventana mientras Inlay estaba en pausa; los
demás conservan su disposición. También está en **Ajustes › General › Tiling**.

Una ventana que sale del mosaico porque macOS la **minimiza**, la pone en **pantalla completa nativa** u
**oculta su app** recuerda su sitio (contenedor, posición, tamaño y la vecina que se quedó con su espacio) y lo
recupera al volver:

- Si su contenedor sigue existiendo, vuelve a su posición y la vecina le devuelve el espacio.
- Si el contenedor desapareció (tenía solo dos ventanas y se aplanó), se vuelve a dividir a la vecina igual que antes.
- Si ya no queda ni contenedor ni vecina, o vuelve en otro workspace (una ventana minimizada reaparece en el
  workspace enfocado), entra como una ventana nueva.

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

- El item es **solo informativo**: el clic izquierdo no hace nada (no cambia de workspace ni abre el menú).
  El **clic derecho** (o ctrl-clic) abre el menú: workspaces, ventana enfocada, layout, modo, config, pausar y
  Ajustes. Con VoiceOver, «pulsar» el item (VO-espacio) abre el menú. Para cambiar de workspace: los atajos, la
  CLI o la sección *Workspaces* del menú.
- **Ajustes…** (⌘, en el menú, o abrir Inlay otra vez desde Aplicaciones) edita esas claves **en tu fichero de
  config**, línea a línea y sin tocar comentarios ni el resto del fichero, y recarga la config. Si la config es
  un enlace simbólico, se escribe en su destino. Si aún no tienes config, el primer cambio crea
  `~/.config/inlay/inlay.toml` a partir de la incluida. Una clave escrita con puntos (`menu-bar.theme = …`) o
  dentro de una tabla en línea no se edita desde Ajustes: su control aparece desactivado. Una subtabla que aún
  no existe (`[menu-bar.colors]`, `[borders.mode-colors]`) se añade a continuación de su tabla madre.

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
| `glow` | `true`, `false` | `false` |
| `glow-radius` | 1 … 40 (puntos) | `12` |
| `[borders.mode-colors]` `<modo>` | color | tabla vacía |

- **Color de la ventana enfocada**: el del modo de atajos activo si tiene entrada en `[borders.mode-colors]`; si
  no, `floating-color` si es flotante; si no, `active-color`. Las demás ventanas usan `inactive-color`.
- Un color **totalmente transparente** (`'#00000000'`) significa «sin borde»: con
  `inactive-color = '#00000000'` solo lleva borde la ventana activa.
- **Sin borde**: ventanas en pantalla completa (la de Inlay y la nativa de macOS) y las ventanas en mosaico que
  tapan, minimizadas, de apps ocultas, popups, las de workspaces no visibles, y la ventana que estás arrastrando
  o redimensionando con el ratón (el borde vuelve al soltar). Los diálogos son ventanas flotantes y sí llevan.
- El borde va **por fuera** del marco de la ventana, en el hueco entre ventanas: no tapa contenido y no recibe
  clics. Conviene que los `gaps` sean al menos el doble de `width` (la config incluida usa 14 con el borde de 4);
  con gaps más pequeños los bordes de dos ventanas vecinas se tocan o se solapan.
- **Glow** (`glow = true`): un resplandor del color del borde alrededor de la ventana **enfocada** (con el color
  que le toque: activo, flotante o de modo), que se desvanece hacia fuera a lo largo de unos `glow-radius` puntos.
  Las ventanas no enfocadas nunca lo llevan. Es exterior: no se dibuja bajo el borde ni sobre la ventana, pero sí
  sobre lo que haya alrededor (el hueco y, si es más ancho que el hueco, el filo de las ventanas vecinas). No
  recibe clics. Es una imagen pequeña que Core Animation estira, así que mover o redimensionar no redibuja nada.
- El radio de las esquinas es fijo: macOS no deja leer el de las ventanas de otras apps. Ajústalo a ojo.
- Los bordes desaparecen al pausar Inlay (`inlay enable off`), al salir y con `enabled = false`.
- **Colores por modo en Ajustes**: la pestaña **Borders** tiene una fila por cada modo de atajos definido en tu
  config (`[mode.<nombre>.binding]`), con selector de color y «Reset», que borra la clave de
  `[borders.mode-colors]`. Si la tabla no existe se crea justo después de `[borders]`. El modo `main` no tiene
  fila: es el modo que está activo siempre, y un color propio sustituiría para siempre a `active-color` y
  `floating-color`, que existen para eso (a mano se puede seguir escribiendo `main = '…'`).

Cada borde es una ventana propia de Inlay, transparente, colocada justo encima de su ventana en el orden de
apilado, así que una ventana flotante de otra app tapa los bordes de las ventanas que tiene detrás. Todo con
API pública de AppKit; no hay código de JankyBorders ni se usa SkyLight.

## Desinstalación

```sh
./uninstall.sh           # cierra Inlay y quita la app, el enlace de la CLI y el ítem de inicio
./uninstall.sh --purge   # además borra tu configuración y las preferencias de la app
```

Busca la app en `/Applications` y en `~/Applications`; con `INSTALL_DIR=…` solo mira en esa carpeta. Al cerrarse,
Inlay devuelve a la pantalla las ventanas de los workspaces no visibles. No toca nada de AeroSpace, AeroMenu ni
`borders`: para volver a ellos, abre AeroSpace y AeroMenu y ejecuta `brew services start borders`.

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

Los tests usan Swift Testing (XCTest no viene en las Command Line Tools, y ya no queda ningún target XCTest).
Todas las suites van anidadas en `InlayTests` (`extension InlayTests { @Suite @MainActor struct FooTest { ... } }`),
que es `.serialized`: los tests comparten el modelo global y no pueden ejecutarse en paralelo.

Para saber qué diría Inlay de un fichero de config cualquiera sin instalar nada (errores y avisos del parser
real):

```sh
INLAY_TEST_CONFIG=~/.aerospace.toml scripts/test.sh --filter ShippedConfigsTest | grep -A8 INLAY_TEST_CONFIG
```

| Ruta | Contenido |
|---|---|
| `Sources/InlayApp` | Punto de entrada de la app (producto `InlayApp`, que en el bundle es `Contents/MacOS/Inlay`) |
| `Sources/AppBundle` | El gestor de ventanas: árbol, comandos, configuración, servidor, interfaz |
| `Sources/Cli` | La CLI `inlay` (cliente del socket `/tmp/com.davidhiguita.inlay-$USER.sock`) |
| `Sources/Common` | Código compartido por la app y la CLI |
| `Sources/BuildInfo` | Versión y hash de git, que `build-app.sh` pasa por variables de entorno |
| `Sources/PrivateApi` | Cabecera de `_AXUIElementGetWindow` |
| `Tests/InlayTests` | Tests con Swift Testing. En `support/` están las ventanas falsas y demás utilidades; en `fixtures/`, configs de ejemplo |
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
