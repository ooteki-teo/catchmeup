# CatchMeUp

> Un asistente de tareas para macOS nativo: suelta capturas, texto, archivos, carpetas o URLs y los organiza en elementos y tareas, y recuerda "dónde lo dejaste y qué sigue".

[简体中文](README.md) · [English](README.en.md) · **Español** · [日本語](README.ja.md) · [한국어](README.ko.md)

CatchMeUp es una **app nativa de un solo archivo** (SwiftUI + Swift 6). Sin Electron y sin Python: todo se ejecuta en local salvo las llamadas a la API de DeepSeek.

---

## Funciones

### Captura unificada (estilo WeChat, pocos clics)
- Un único campo para todo: **texto / URL / ruta de archivo / arrastrar archivos / carpetas / pegar una captura (⌘V) / seleccionar una región** — el tipo se detecta solo.
- Enrutado inteligente: las URLs se descargan, las rutas se leen, las imágenes van a OCR o al modelo de visión.
- Atajo global (por defecto `⌘⇧M`, **configurable**): selecciona una región desde cualquier lugar → la app pasa al frente y la analiza.

### Organización con IA (DeepSeek)
- Modelo por defecto `deepseek-flash` (admite imágenes); puedes cambiar a `deepseek-v4-pro`.
- Genera título, resumen, etiquetas, categoría y dos resultados estructurados:
  - **Tareas**: pendientes con fecha límite explícita;
  - **Handoff**: resumen del proyecto (objetivos / enfoque / progreso detallado / siguientes pasos / riesgos).
- Las capturas usan primero el modelo de visión y, si falla, el **OCR Vision** local (chino + inglés).
- Una carpeta se resume como "README (si existe) + árbol de directorios + una línea por archivo"; nunca se vuelca el texto completo.

### Tareas (agrupadas por fecha, un clic)
- La vista "Tareas" agrupa en **Vencidas / Hoy / Mañana / Esta semana / Después / Sin fecha / Completadas**.
- Añade con una línea + Intro; marca el círculo para completar, toca la fecha para reprogramar, el punto para la prioridad.
- Notificaciones locales a tiempo (suenan aunque la app esté cerrada), con repetición diaria / semanal / mensual.
- Opción de escribir las tareas con vencimiento en el **Calendario** del sistema.

### Handoff (seguimiento continuo)
- Cada elemento de handoff tiene un "update" incremental: vuelve a leer el origen y reutiliza el handoff anterior, conservando lo válido y añadiendo solo cambios.
- Inicia / termina sesiones y genera un resumen copiable como Markdown.

### Más
- Barra de menús: nota rápida, captura, portapapeles, próximos elementos.
- **Estadísticas de uso de tokens** (Ajustes → DeepSeek): llamadas / entrada / salida / total, por modelo.
- La clave API se guarda en un archivo local, no en el Llavero — **sin avisos de permiso**.
- Todos los permisos (notificaciones / calendario / grabación de pantalla) se **piden solo al pulsar en Ajustes** — nada aparece al iniciar.
- **Idiomas: 简体中文, English, Español, 日本語, 한국어** (Ajustes → Idioma; seguir el sistema o elegir uno).

---

## Requisitos

- macOS 14.0 o superior (verificado en Apple Silicon)
- Xcode o Command Line Tools (Swift 6)
- Una clave API de [DeepSeek](https://platform.deepseek.com/)
- Opcional: un certificado Apple Development (para recordar permisos entre compilaciones, ver abajo)

---

## Inicio rápido

```bash
bash scripts/build.sh      # compila y empaqueta dist/CatchMeUp.app
open "dist/CatchMeUp.app"
bash scripts/test.sh       # o: swift test
```

Primer uso:

1. **Ajustes → DeepSeek**: pega la clave API y pulsa **Guardar**.
2. **Ajustes → Permisos**: concede lo que necesites (Notificaciones, Calendario, Grabación de pantalla).
3. Pulsa `⌘⇧M` (configurable en **Ajustes → General**) para seleccionar una región y analizarla.

---

## Uso

| Escenario | Acción |
| --- | --- |
| Anotar texto | Escribe en el cuadro del Espacio y pulsa Intro |
| Guardar una web | Pega la URL y pulsa Intro |
| Organizar una carpeta | Arrástrala dentro (se trata como handoff) |
| Organizar una captura | `⌘⇧M`, el botón de cámara o ⌘V |
| Ver un elemento | Clic en la tarjeta → ventana aparte (movible/redimensionable, con **Actualizar**) |
| Tareas | Escribe una línea en la pestaña Tareas; reprograma/prioriza/completa en línea |
| Handoff | Genera un resumen en la pestaña Handoff o actualiza una tarjeta |

---

## Estructura

```text
catchmeup/
├── Package.swift                 # manifiesto SwiftPM (macOS 14+, sin dependencias)
├── Sources/
│   ├── CatchMeUpCore/            # modelos, almacenamiento, IA, OCR, calendario, recordatorios
│   │   └── L10n.swift            # localización (zh/en/es/ja/ko)
│   └── CatchMeUpApp/             # capa SwiftUI
├── Tests/CatchMeUpCoreTests/
└── scripts/
```

---

## Datos y privacidad

- Carpeta de datos: `~/Library/Application Support/CatchMeUp/` (`catchmeup.db`, `storage/`, `secrets.json`, `usage.json`).
- La clave API vive en `secrets.json` (permisos 0600); también puedes usar la variable `DEEPSEEK_API_KEY`.
- DeepSeek solo se llama al organizar contenido; el resto se queda en tu Mac.

---

## Permisos y firma

macOS recuerda permisos como la Grabación de pantalla según la **firma de código**. Con firma **ad-hoc** el requisito es un `cdhash` que cambia en cada compilación, así que el sistema re-pregunta.

`scripts/build.sh` usa tu certificado **Apple Development** si existe, para que el permiso persista:

```bash
CODESIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" bash scripts/build.sh
```

Para una **compilación limpia y compartible** sin identidad personal (p. ej. para un release de GitHub):

```bash
bash scripts/package-release.sh   # → dist/CatchMeUp-<version>.zip (ad-hoc, sin email/Team ID)
```

---

## Preguntas frecuentes

**P: La Grabación de pantalla se pide una y otra vez.**
R: Recompila con un certificado (arriba) y concédela una vez en Ajustes → Permisos.

**P: ¿Sirve sin conceder permisos?**
R: Sí. Solo pierdes notificaciones, calendario y capturas.

**P: ¿Puedo evitar DeepSeek?**
R: La organización y el handoff dependen de la API; sin clave aún puedes gestionar tareas a mano.

---

## Licencia

[MIT](LICENSE)
