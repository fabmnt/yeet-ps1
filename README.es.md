# yeet

> Deja de gastar tokens de tus agentes de código principales (Codex, Claude Code) solo para crear mensajes de commit, títulos y descripciones de PRs. **yeet** te permite usar modelos gratuitos de OpenRouter para lograr esto sin problemas.

`yeet` es un asistente CLI orientado a Windows para trabajar con pull requests de GitHub.

Utiliza:
- `git` para operaciones de branch/commit/push
- `gh` (GitHub CLI) para buscar/crear/editar/fusionar PRs
- OpenRouter (`OPENROUTER_API_KEY`) para generar mensajes de commit y títulos/descripciones de PRs a partir de diffs

El punto de entrada del comando es `yeet.cmd`, que invoca `yeet.ps1`.

## Requisitos

- PowerShell
- `git` instalado y disponible en `PATH`
- `gh` instalado y autenticado (`gh auth login`)
- Variable de entorno `OPENROUTER_API_KEY` configurada (ver [Configuración](#configuración) más abajo)

Opcional:
- `OPENROUTER_MODEL_ID` (o `OPENROUTER_MODEL`) para sobrescribir el modelo por defecto

## Configuración

### Clave API de OpenRouter

1. Obtén tu clave API gratuita en [OpenRouter](https://openrouter.ai/keys)
2. Configura la variable de entorno `OPENROUTER_API_KEY`:

   **PowerShell (sesión actual):**
   ```powershell
   $env:OPENROUTER_API_KEY = "sk-or-v1-..."
   ```

   **PowerShell (permanente):**
   ```powershell
   [Environment]::SetEnvironmentVariable("OPENROUTER_API_KEY", "sk-or-v1-...", "User")
   ```

   **Símbolo del sistema de Windows:**
   ```cmd
   setx OPENROUTER_API_KEY "sk-or-v1-..."
   ```

### Modelo de OpenRouter (Opcional)

Por defecto, yeet usa el modelo gratuito: `nvidia/nemotron-3-super-120b-a12b:free`

Para usar un modelo diferente, configura una de estas variables de entorno:

```powershell
# Opción 1: OPENROUTER_MODEL_ID (recomendado)
$env:OPENROUTER_MODEL_ID = "anthropic/claude-3.5-sonnet"

# Opción 2: OPENROUTER_MODEL (alternativa)
$env:OPENROUTER_MODEL = "google/gemini-pro"
```

Encuentra modelos disponibles en [openrouter.ai/models](https://openrouter.ai/models).

## Instalación

Instalar desde [PowerShell Gallery](https://www.powershellgallery.com/packages/yeet):

```powershell
Install-Module -Name yeet -Scope CurrentUser
Import-Module yeet
```

Agrega `Import-Module yeet` a tu perfil de PowerShell para carga automática.

## Configuración Inicial

Después de la instalación, necesitas configurar tu clave API de OpenRouter. Puedes hacerlo de dos formas:

### Opción 1: Configuración Interactiva (Recomendado)

Ejecuta el comando de configuración e introduce tu clave API cuando se te solicite:

```powershell
yeet -Setup
```

O usa la forma abreviada:

```powershell
yeet -s
```

La configuración:
- Te solicitará tu clave API de OpenRouter (la entrada está oculta por seguridad)
- Guardará la clave en tu perfil de PowerShell para persistencia entre sesiones
- Configurará la clave para la sesión actual inmediatamente

### Opción 2: Configuración Manual

Si prefieres configurar la variable de entorno manualmente:

**PowerShell (sesión actual):**
```powershell
$env:OPENROUTER_API_KEY = "sk-or-v1-..."
```

**PowerShell (permanente):**
```powershell
[Environment]::SetEnvironmentVariable("OPENROUTER_API_KEY", "sk-or-v1-...", "User")
```

**Símbolo del sistema de Windows:**
```cmd
setx OPENROUTER_API_KEY "sk-or-v1-..."
```

**Nota:** Si ejecutas `yeet` sin una clave API configurada (excepto para `-v` o `-h`), automáticamente entrará en modo de configuración y te solicitará la clave.

## Uso

```powershell
yeet [-DebugMode] [-Merge] [-Update [-New]] [-Push] [-Setup] [-Version] [-Help]
```

## Argumentos CLI

- `-Help`, `-h`
  - Muestra la ayuda y sale.

- `-Setup`, `-s`
  - Entra en modo de configuración interactiva para configurar la clave API de OpenRouter.

- `-DebugMode`, `-D`
  - Habilita el registro de depuración.

- `-Merge`, `-m`
  - Fusiona el PR abierto de la rama actual (squash + eliminar rama).
  - Luego cambia a la rama base del PR y hace pull de los últimos cambios.
  - Falla si existen cambios sin commit.

- `-Update`, `-u`
  - Para un PR abierto existente en la rama actual.
  - Usa IA para generar un mensaje de commit a partir de los cambios actuales.
  - Prepara todos los cambios, hace commit, y push a la rama del PR.

- `-New`, `-n`
  - Solo es válido con `-Update`.
  - También regenera y actualiza el título/cuerpo del PR (no solo commit + push).

- `-Push`
  - Genera un mensaje de commit a partir de los cambios actuales y hace push directamente sin crear un PR.
  - Muestra el mensaje de commit generado y espera confirmación.
  - No se puede combinar con `-Merge` o `-Update`.

- `-Version`, `-v`
  - Muestra la versión actual de yeet.

## Comportamiento (por modo)

### Modo por defecto (`yeet` sin flags)

- Si tienes cambios sin commit:
  - Genera mensaje de commit + título/cuerpo del PR a partir del diff.
  - Muestra una vista previa y espera confirmación.
  - Crea una rama a partir del título generado, hace commit, push, y abre un PR.

- Si no tienes cambios sin commit:
  - Si estás en la rama por defecto: sale con error.
  - Si estás en una rama de feature y el PR existe: imprime la info del PR y sale.
  - Si estás en una rama de feature sin PR abierto: genera título/cuerpo del PR a partir del diff de la rama, y luego crea el PR.

### Modo actualización (`yeet -u`)

- Requiere:
  - cambios sin commit
  - la rama actual no es la rama por defecto
  - PR abierto existente para la rama actual
- Hace commit y push de los cambios a la rama del PR.
- Con `-n`, también actualiza el título/cuerpo del PR.

### Modo fusión (`yeet -m`)

- Requiere PR abierto para la rama actual y un working tree limpio.
- Ejecuta `gh pr merge --squash --delete-branch`.
- Cambia a la rama base del PR y hace pull de los últimos cambios de origin.

### Modo push (`yeet -p`)

- Requiere cambios sin commit.
- Usa IA para generar un mensaje de commit a partir de los cambios actuales.
- Muestra una vista previa y espera confirmación.
- Hace commit de todos los cambios y push directamente a la rama actual sin crear un PR.
- No se puede combinar con `-Merge` o `-Update`.

## Ejemplos

```powershell
# Configuración inicial (configurar clave API de OpenRouter)
yeet -s

# Crear un PR a partir de cambios locales
yeet

# Actualizar el PR actual con nuevos commits
yeet -u

# Actualizar el PR actual y refrescar título/cuerpo
yeet -u -n

# Fusionar el PR de la rama actual
yeet -m

# Generar mensaje de commit y hacer push directamente (sin PR)
yeet -Push

# Mostrar version
yeet -v

# Mostrar ayuda
yeet -h
```

## Notas

- Esta herramienta es interactiva y pide confirmación de ENTER/ESC antes de realizar acciones de crear/actualizar/fusionar.
- Sale con estado distinto de cero en caso de errores de validación o de API/auth.
