# yeet

> Deja de gastar tokens de tus agentes de codigo principales (Codex, Claude Code) solo para crear mensajes de commit, titulos y descripciones de PRs. **yeet** te permite usar modelos gratuitos de OpenRouter para lograr esto sin problemas.

`yeet` es un asistente CLI orientado a Windows para trabajar con pull requests de GitHub.

Utiliza:
- `git` para operaciones de branch/commit/push
- `gh` (GitHub CLI) para buscar/crear/editar/fusionar PRs
- OpenRouter (`OPENROUTER_API_KEY`) para generar mensajes de commit y titulos/descripciones de PRs a partir de diffs

El punto de entrada del comando es `yeet.cmd`, que invoca `yeet.ps1`.

## Requisitos

- PowerShell
- `git` instalado y disponible en `PATH`
- `gh` instalado y autenticado (`gh auth login`)
- Variable de entorno `OPENROUTER_API_KEY` configurada (ver [Configuracion](#configuracion) mas abajo)

Opcional:
- `OPENROUTER_MODEL_ID` (o `OPENROUTER_MODEL`) para sobrescribir el modelo por defecto

## Configuracion

### Clave API de OpenRouter

1. Obtén tu clave API gratuita en [OpenRouter](https://openrouter.ai/keys)
2. Configura la variable de entorno `OPENROUTER_API_KEY`:

   **PowerShell (sesion actual):**
   ```powershell
   $env:OPENROUTER_API_KEY = "sk-or-v1-..."
   ```

   **PowerShell (permanente):**
   ```powershell
   [Environment]::SetEnvironmentVariable("OPENROUTER_API_KEY", "sk-or-v1-...", "User")
   ```

   **Simbolo del sistema de Windows:**
   ```cmd
   setx OPENROUTER_API_KEY "sk-or-v1-..."
   ```

## Instalacion

Instalar desde [PowerShell Gallery](https://www.powershellgallery.com/packages/yeet):

```powershell
Install-Module -Name yeet -Scope CurrentUser
Import-Module yeet
```

Agrega `Import-Module yeet` a tu perfil de PowerShell para carga automatica.

## Uso

```powershell
yeet [-DebugMode] [-Merge] [-Update [-New]] [-Push] [-Version] [-Help]
```

## Argumentos CLI

- `-Help`, `-h`
  - Muestra la ayuda y sale.

- `-DebugMode`, `-D`
  - Habilita el registro de depuracion.

- `-Merge`, `-m`
  - Fusiona el PR abierto de la rama actual (squash + eliminar rama).
  - Luego cambia a la rama base del PR y hace pull de los ultimos cambios.
  - Falla si existen cambios sin commit.

- `-Update`, `-u`
  - Para un PR abierto existente en la rama actual.
  - Usa IA para generar un mensaje de commit a partir de los cambios actuales.
  - Prepara todos los cambios, hace commit, y push a la rama del PR.

- `-New`, `-n`
  - Solo es valido con `-Update`.
  - Tambien regenera y actualiza el titulo/cuerpo del PR (no solo commit + push).

- `-Push`
  - Genera un mensaje de commit a partir de los cambios actuales y hace push directamente sin crear un PR.
  - Muestra el mensaje de commit generado y espera confirmacion.
  - No se puede combinar con `-Merge` o `-Update`.

- `-Version`, `-v`
  - Muestra la version actual de yeet.

## Comportamiento (por modo)

### Modo por defecto (`yeet` sin flags)

- Si tienes cambios sin commit:
  - Genera mensaje de commit + titulo/cuerpo del PR a partir del diff.
  - Muestra una vista previa y espera confirmacion.
  - Crea una rama a partir del titulo generado, hace commit, push, y abre un PR.

- Si no tienes cambios sin commit:
  - Si estas en la rama por defecto: sale con error.
  - Si estas en una rama de feature y el PR existe: imprime la info del PR y sale.
  - Si estas en una rama de feature sin PR abierto: genera titulo/cuerpo del PR a partir del diff de la rama, y luego crea el PR.

### Modo actualizacion (`yeet -u`)

- Requiere:
  - cambios sin commit
  - la rama actual no es la rama por defecto
  - PR abierto existente para la rama actual
- Hace commit y push de los cambios a la rama del PR.
- Con `-n`, tambien actualiza el titulo/cuerpo del PR.

### Modo fusion (`yeet -m`)

- Requiere PR abierto para la rama actual y un working tree limpio.
- Ejecuta `gh pr merge --squash --delete-branch`.
- Cambia a la rama base del PR y hace pull de los ultimos cambios de origin.

### Modo push (`yeet -p`)

- Requiere cambios sin commit.
- Usa IA para generar un mensaje de commit a partir de los cambios actuales.
- Muestra una vista previa y espera confirmacion.
- Hace commit de todos los cambios y push directamente a la rama actual sin crear un PR.
- No se puede combinar con `-Merge` o `-Update`.

## Ejemplos

```powershell
# Crear un PR a partir de cambios locales
yeet

# Actualizar el PR actual con nuevos commits
yeet -u

# Actualizar el PR actual y refrescar titulo/cuerpo
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

- Esta herramienta es interactiva y pide confirmacion de ENTER/ESC antes de crear/actualizar/fusionar acciones.
- Sale con estado no-cero en caso de errores de validacion o de API/auth.