return {
  -- ─────────────────────────────────────────────────────────────────────────────
  -- Inlay — configuración de ejemplo
  --
  -- Ubicación: ~/.config/inlay/inlay.lua   (o ~/.inlay.lua; si existen los dos,
  -- Inlay avisa de la ambigüedad y no carga ninguno).
  --
  -- El esquema es el de AeroSpace, con las claves en camelCase, más tres tablas
  -- nuevas: tiling, menuBar y borders:
  --   · todo lo de AeroSpace sigue significando lo mismo;
  --   · 'accordion' ya no existe: donde aparezca se acepta con un aviso y se
  --     trata como 'tiles' (ver el final de este fichero);
  --   · las tablas nuevas son opcionales: si faltan, valen sus valores por defecto.
  --
  -- Cualquier clave desconocida es un error (como en AeroSpace), así una errata
  -- no pasa desapercibida. Con autoReloadConfig los cambios se aplican al
  -- guardar; si el fichero tiene errores, sigue activa la configuración anterior.
  --
  -- Colores: '#RRGGBB', '#RRGGBBAA' (AA = opacidad) o 'system-accent' (el color
  -- de acento de Ajustes del Sistema › Apariencia). En [menuBar.colors] existe
  -- además 'auto': blanco sobre barra oscura y negro sobre barra clara.
  -- ─────────────────────────────────────────────────────────────────────────────

  configVersion = 2,
  -- Sin tema: los colores de abajo son los valores por defecto del código
  theme = {},

  -- Abrir Inlay al iniciar sesión.                              (defecto: false)
  startAtLogin = true,

  -- Recargar este fichero al guardarlo.                         (defecto: false)
  -- La ventana de Ajustes lo necesita para que sus cambios se vean al momento;
  -- si está en false, Ajustes recarga la config a mano después de escribir.
  autoReloadConfig = true,

  -- Comandos al arrancar, después de leer la config.
  afterStartupCommand = {},

  -- Normalizaciones del árbol (heredadas de AeroSpace; conviene dejarlas en true:
  -- el auto-tiling dwindle se apoya en ellas).
  enableNormalizationFlattenContainers = true,
  enableNormalizationOppositeOrientationForNestedContainers = true,

  -- Orientación del contenedor raíz de un workspace vacío:
  -- 'horizontal' | 'vertical' | 'auto' (horizontal en monitor apaisado).
  -- Con dwindle solo importa para la primera ventana; la segunda ya decide sola.
  defaultRootContainerOrientation = 'auto',

  -- Layout del contenedor raíz. En Inlay solo existe 'tiles'.
  defaultRootContainerLayout = 'tiles',

  -- Workspaces que existen siempre, aunque estén vacíos. Son los que la barra
  -- dibuja atenuados.
  persistentWorkspaces = { '1', '2', '3', '4', '5', '6', '7' },

  -- El cursor acompaña al foco.
  onFocusedMonitorChanged = { 'move-mouse monitor-lazy-center' },
  onFocusChanged = { 'move-mouse window-lazy-center' },

  -- cmd-h oculta apps como siempre en macOS.
  automaticallyUnhideMacosHiddenApps = false,


  -- ─── Mosaico ─────────────────────────────────────────────────────────────────
  tiling = {
    -- Dónde entra una ventana nueva en mosaico.
    --   'dwindle'        La nueva divide en dos la ventana enfocada. Si la enfocada
    --                    es más ancha que alta quedan lado a lado; si no, apiladas.
    --                    La nueva va a la derecha o debajo. Inspirado en Hyprland.
    --   'after-focused'  El comportamiento de AeroSpace: la nueva entra como hermana
    --                    después de la enfocada y todas las hermanas se reparten
    --                    el espacio.
    newWindowPlacement = 'dwindle', -- defecto: 'dwindle'

    -- Con dwindle: fracción del hueco que conserva la ventana que se divide.
    -- 0.5 = mitades iguales; 0.6 = la original se queda el 60 %. Rango 0.1 – 0.9.
    splitRatio = 0.5, -- defecto: 0.5

    -- Con dwindle: qué ventana divide la ventana nueva.
    --   'focused'  La enfocada. Si no está en mosaico en ese workspace (es flotante,
    --              o la ventana va a otro workspace), la más reciente en mosaico.
    --   'cursor'   La ventana en mosaico que está bajo el cursor del ratón, como en
    --              Hyprland. Si no hay ninguna (el cursor está en un gap, en otro
    --              monitor o sobre una ventana a pantalla completa, o el workspace
    --              no está visible), igual que 'focused'.
    splitTarget = 'focused', -- defecto: 'focused'

    -- Cómo se reparten las ventanas que YA están abiertas cuando Inlay arranca (o
    -- cuando se reanuda con `inlay enable on`), workspace por workspace. Las que se
    -- abren después siguen `newWindowPlacement`.
    --   'grid'     Rejilla equilibrada: ceil(√n) columnas y las filas que hagan
    --              falta. La última fila reparte su ancho entre las ventanas que
    --              tenga: 5 ventanas son 3 arriba y 2 abajo.
    --   'row'      Una sola fila, todas al mismo ancho.
    --   'dwindle'  Sin reparto: entran una detrás de otra, como ventanas nuevas
    --              (con dwindle, una espiral con las últimas muy pequeñas).
    startupLayout = 'grid', -- defecto: 'grid'

    -- Tamaño mínimo, en puntos, que `resize` y el arrastre de un borde con el ratón
    -- dejan a una ventana en mosaico: al llegar ahí dejan de encoger, sin error
    -- (`resize` sigue saliendo con 0). Solo limita el redimensionado: si las
    -- ventanas de un workspace no caben con este tamaño, el reparto les da menos.
    -- Rango 20 – 500.
    minWindowSize = 100, -- defecto: 100
  },


  -- ─── Barra de menús ──────────────────────────────────────────────────────────
  menuBar = {
    -- Mostrar el item de Inlay en la barra de menús. Con false, Inlay sigue
    -- funcionando y se maneja con atajos y con el CLI.            (defecto: true)
    enabled = true,

    -- Forma del item:
    --   'chips'        Solo los workspaces: fondo tenue si tienen ventanas, sólido
    --                  el enfocado, atenuados los vacíos. El de Aeromenu.
    --   'hypr'         Nombres sin fondo en huecos del mismo ancho y un cuadrado en
    --                  lugar del enfocado (lleva la inicial del modo si no es main).
    --   'minimal'      Solo el workspace enfocado.
    --   'liquid'       Un punto por workspace y una gota con el nombre del enfocado,
    --                  que fluye al siguiente dejando una estela.
    --   'dms'          Workspaces redondos sobre una pista tenue y el enfocado una
    --                  píldora con su nombre, como Dank Material Shell.
    theme = 'liquid', -- defecto: 'liquid'

    -- Dibujar más tenues los workspaces sin ventanas.             (defecto: true)
    dimEmptyWorkspaces = true,

    -- Mostrar el modo de atajos cuando no es 'main': su inicial en el marcador del
    -- workspace enfocado (el chip, o el cuadrado de 'hypr'), sin cambiar el ancho
    -- del item.                                                   (defecto: false)
    showMode = true,

    colors = {
      -- Los cuatro son opcionales. Con los valores por defecto el item es monocromo
      -- y se adapta a la barra, igual que Aeromenu.
      accent = 'auto', -- marcador con el modo de atajos  (defecto: 'auto' = como 'focused')
      focused = 'auto', -- fondo del workspace enfocado    (defecto: 'auto')
      occupied = 'auto', -- workspaces con ventanas         (defecto: 'auto')
      empty = 'auto', -- workspaces vacíos               (defecto: 'auto')
    },
  },
  -- Un ejemplo con color (el naranja Noctua):
  --   focused  = '#D19A66'
  --   occupied = '#ABB2BF'
  --   empty    = '#6B7280'
  -- Con un color fijo en `focused`, el nombre se dibuja en blanco o en negro,
  -- el que más contraste. `occupied` colorea el nombre y, al 16 %, su fondo.


  -- ─── Bordes de ventana ───────────────────────────────────────────────────────
  borders = {
    -- Llevan borde las ventanas normales, en mosaico o flotantes. No lo llevan los
    -- diálogos y hojas (lo que Inlay detecta como diálogo y pone flotante solo),
    -- los popups ni las ventanas a pantalla completa.
    enabled = true, -- defecto: true

    -- Grosor en puntos. El borde se dibuja por fuera del marco de la ventana, así
    -- que conviene que los gaps sean al menos el doble.            (defecto: 4)
    width = 4,

    -- Radio de las esquinas, en puntos. Inlay no puede leer el radio real de las
    -- ventanas de otras apps: ajústalo a ojo. 16 es una aproximación para macOS 26
    -- y posteriores; en macOS 14 y 15 queda mejor 10.              (defecto: 16)
    cornerRadius = 16,

    activeColor = 'system-accent', -- ventana enfocada en mosaico   (defecto: 'system-accent')
    inactiveColor = '#8E8E9373', -- el resto de ventanas          (defecto: '#8E8E9373')
    floatingColor = '#BF5AF2', -- ventana enfocada flotante     (defecto: '#BF5AF2')
    -- Para ver solo el borde de la ventana activa:  inactiveColor = '#00000000'

    -- Resplandor del color del borde alrededor de la ventana enfocada (activa,
    -- flotante o con color de modo). Las no enfocadas nunca lo llevan. Es exterior:
    -- no tapa la ventana ni recibe clics.                          (defecto: false)
    glow = false,
    -- Radio de desenfoque en puntos: hasta dónde llega, más o menos. Rango 1 – 40.
    glowRadius = 12, -- (defecto: 12)

    modeColors = {
      -- Color del borde de la ventana enfocada mientras está activo un modo de
      -- atajos. Tiene prioridad sobre activeColor y floatingColor. Un modo sin
      -- entrada conserva el color normal. Vacío por defecto. También se edita en
      -- Ajustes › Borders (una fila por modo definido aquí abajo, menos `main`).
      resize = '#30D158',
      service = '#FF453A',
    },
  },


  -- ─── Separaciones ────────────────────────────────────────────────────────────
  -- Con bordes de 4 pt, 14 pt dejan 6 pt de aire entre los bordes de dos ventanas
  -- vecinas. Cada valor puede ser una constante o depender del monitor:
  --   outer = { top = { { monitor = { main = 14 } }, 24 } }
  gaps = {
    inner = { horizontal = 14, vertical = 14 },
    outer = { left = 14, right = 14, top = 14, bottom = 14 },
  },


  -- ─── Atajos: modo principal ──────────────────────────────────────────────────
  -- Modificadores: cmd, alt, ctrl, shift. Los atajos no se heredan de la config
  -- por defecto: los que no estén aquí no existen.
  mode = {
    main = {
      binding = {
        -- Ir a un workspace
        ['cmd-alt-ctrl-j'] = 'workspace 1', -- terminales
        ['cmd-alt-ctrl-k'] = 'workspace 2', -- editores
        ['cmd-alt-ctrl-l'] = 'workspace 3', -- navegadores
        ['cmd-alt-ctrl-i'] = 'workspace 4', -- mensajería
        ['cmd-alt-ctrl-o'] = 'workspace 5', -- IA
        ['cmd-alt-ctrl-p'] = 'workspace 6', -- segunda pantalla

        -- Mover la ventana enfocada a un workspace
        ['cmd-alt-shift-j'] = 'move-node-to-workspace 1',
        ['cmd-alt-shift-k'] = 'move-node-to-workspace 2',
        ['cmd-alt-shift-l'] = 'move-node-to-workspace 3',
        ['cmd-alt-shift-i'] = 'move-node-to-workspace 4',
        ['cmd-alt-shift-o'] = 'move-node-to-workspace 5',
        ['cmd-alt-shift-p'] = 'move-node-to-workspace 6',

        -- Foco
        ['cmd-alt-left'] = 'focus left',
        ['cmd-alt-down'] = 'focus down',
        ['cmd-alt-up'] = 'focus up',
        ['cmd-alt-right'] = 'focus right',

        -- Mover la ventana por el árbol
        ['cmd-alt-ctrl-left'] = 'move left',
        ['cmd-alt-ctrl-down'] = 'move down',
        ['cmd-alt-ctrl-up'] = 'move up',
        ['cmd-alt-ctrl-right'] = 'move right',

        -- Girar la división del contenedor de la ventana enfocada (lado a lado ↔
        -- apiladas). Es el «togglesplit» de Hyprland.
        ['cmd-alt-slash'] = 'layout horizontal vertical',

        -- Igualar los tamaños de las ventanas del workspace después de redimensionar.
        -- Es la tecla que en AeroSpace cambiaba a accordion, que Inlay no tiene.
        -- También está en el modo service, en la tecla b.
        ['cmd-alt-comma'] = 'balance-sizes',

        ['cmd-alt-ctrl-enter'] = 'fullscreen',

        ['cmd-alt-ctrl-m'] = 'mode service',
        ['cmd-alt-ctrl-n'] = 'mode resize',
      },
    },


    -- ─── Atajos: modo service ────────────────────────────────────────────────────
    service = {
      binding = {
        esc = { 'reload-config', 'mode main' },
        ['cmd-alt-ctrl-m'] = 'mode main', -- la tecla que entra también sale
        r = { 'flatten-workspace-tree', 'mode main' }, -- restablecer la distribución
        b = { 'balance-sizes', 'mode main' }, -- igualar tamaños
        f = { 'layout floating tiling', 'mode main' }, -- flotante ↔ mosaico

        ['cmd-alt-ctrl-left'] = { 'join-with left', 'mode main' },
        ['cmd-alt-ctrl-down'] = { 'join-with down', 'mode main' },
        ['cmd-alt-ctrl-up'] = { 'join-with up', 'mode main' },
        ['cmd-alt-ctrl-right'] = { 'join-with right', 'mode main' },
      },
    },


    -- ─── Atajos: modo resize ─────────────────────────────────────────────────────
    resize = {
      binding = {
        esc = 'mode main',
        ['cmd-alt-ctrl-n'] = 'mode main',
        left = 'resize width -50',
        right = 'resize width +50',
        up = 'resize height +50',
        down = 'resize height -50',
        minus = 'resize smart -50',
        equal = 'resize smart +50',
      },
    },
  },


  -- ─── Reglas al detectar una ventana ──────────────────────────────────────────
  -- Se evalúan en orden; la primera que coincide se aplica y corta, salvo que
  -- lleve checkFurtherCallbacks = true. Las ventanas que una regla deja en
  -- 'floating' no entran en el mosaico ni dividen a nadie.

  -- Cada app, a su workspace
  onWindowDetected = {
    {
      match = { appId = 'com.mitchellh.ghostty' },
      run = { 'layout tiling', 'move-node-to-workspace 1' },
    },

    {
      match = { appId = 'dev.zed.Zed' },
      run = { 'layout tiling', 'move-node-to-workspace 2' },
    },

    {
      match = { appId = 'com.microsoft.VSCode' },
      run = { 'layout tiling', 'move-node-to-workspace 2' },
    },

    {
      match = { appId = 'app.zen-browser.zen' },
      run = { 'layout tiling', 'move-node-to-workspace 3' },
    },

    {
      match = { appId = 'com.google.Chrome' },
      run = { 'layout tiling', 'move-node-to-workspace 3' },
    },

    {
      match = { appId = 'ru.keepcoder.Telegram' },
      run = { 'layout tiling', 'move-node-to-workspace 4' },
    },

    {
      match = { appId = 'net.whatsapp.WhatsApp' },
      run = { 'layout tiling', 'move-node-to-workspace 4' },
    },

    {
      match = { appId = 'com.anthropic.claudefordesktop' },
      run = { 'layout tiling', 'move-node-to-workspace 5' },
    },

    -- Apps que flotan siempre
    {
      match = { appId = 'com.apple.finder' },
      run = { 'layout floating' },
    },

    {
      match = { appId = 'com.apple.systempreferences' },
      run = { 'layout floating' },
    },

    {
      match = { appId = 'com.apple.Music' },
      run = { 'layout floating' },
    },

    {
      match = { appId = 'com.apple.calculator' },
      run = { 'layout floating' },
    },
  },


  -- ─── Si vienes de AeroSpace ──────────────────────────────────────────────────
  -- Estas formas siguen siendo válidas en Inlay, con un aviso al cargar:
  --
  --   defaultRootContainerLayout = 'accordion'   →  se trata como 'tiles'
  --   accordionPadding = 30                        →  se ignora
  --   'layout accordion', 'layout h_accordion',
  --   'layout v_accordion' (en atajos y reglas)     →  se tratan como 'layout tiles'
  --   'layout tiles accordion' (alternar)           →  queda en 'layout tiles'
  --
  -- El aviso aparece en `inlay reload-config` y en Ajustes › General › Estado.
}
