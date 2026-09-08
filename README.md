# Optimizador de FPS y fluidez para League of Legends

Toolkit en PowerShell para reducir tirones y mejorar la fluidez de League of
Legends en Windows, con capacidad de medir objetivamente si un cambio realmente
ayudo (FPS, 1% low, jitter) usando PresentMon.

## Que hace y que NO hace

**Si hace:** ajustes reversibles a nivel de **sistema operativo** — plan de
energia, prioridad del proceso del juego, scheduler multimedia (MMCSS),
servicios en segundo plano, Game DVR/Modo Juego, algoritmo de Nagle, QoS de
red, y preferencia de GPU dedicada para el ejecutable del juego.

**NO hace, a proposito:**
- No toca memoria, hilos ni el proceso de League of Legends/League Client en
  ejecucion, ni inyecta codigo. League usa **Vanguard**, un anti-cheat a
  nivel de kernel; cualquier interaccion con el proceso del juego puede
  derivar en sancion de cuenta. Todo aqui opera sobre configuracion del
  sistema, nunca sobre el juego en si.
- No edita `PersistedSettings.json` (la config grafica in-game). Ese archivo
  se sincroniza con el servidor de Riot por cuenta; una edicion manual puede
  ser sobrescrita sin aviso en el proximo login. En vez de eso, el script
  imprime una checklist de ajustes recomendados para aplicar tu mismo desde
  el cliente.
- No cambia el DNS del sistema (afectaria a todo el equipo, no solo al
  juego) ni automatiza el NVIDIA Control Panel (requiere su API privada o
  una herramienta de terceros que no forma parte de este proyecto).

## Requisitos

- Windows 10/11, PowerShell (ejecutar como **Administrador**).
- League of Legends instalado (se detecta automaticamente).
- Conexion a internet solo para `benchmark\Get-PresentMon.ps1` (descarga el
  binario oficial desde `github.com/GameTechDev/PresentMon`) y para la
  instalacion via `irm | iex`.

## Instalacion en un paso (recomendado)

Abre PowerShell (no hace falta que sea como Administrador, la GUI se eleva
sola) y pega:

```powershell
irm https://raw.githubusercontent.com/compocl/lol-fps-optimizer/main/install.ps1 | iex
```

Esto descarga el proyecto a `%LOCALAPPDATA%\lol-fps-optimizer` y abre la
interfaz grafica (`Gui.ps1`), que pedira permisos de Administrador via UAC.
Puedes volver a abrir la GUI en cualquier momento sin reinstalar haciendo
doble clic en `%LOCALAPPDATA%\lol-fps-optimizer\Iniciar-Optimizador.cmd`.

### Sobre la politica de ejecucion de PowerShell

Por defecto, Windows bloquea correr archivos `.ps1` sueltos ("running
scripts is disabled on this system"). **No hace falta que cambies nada**:
tanto `install.ps1` como `Gui.ps1` como `Iniciar-Optimizador.cmd` siempre se
lanzan con `-ExecutionPolicy Bypass` en su propio proceso, asi que funcionan
en cualquier equipo sin tocar tu configuracion global.

Ese `Bypass` es **por proceso**: no persiste, no requiere admin, y no afecta
a ningun otro programa. Solo si quieres correr los `.ps1` tu mismo de forma
directa (por ejemplo `.\Optimize-LoL.ps1` en una consola normal, sin pasar
por la GUI ni por `install.ps1`) necesitas una de estas dos opciones:

```powershell
# Opcion A: bypass puntual, solo para esa consola (no persiste)
powershell -ExecutionPolicy Bypass -File .\Optimize-LoL.ps1

# Opcion B: habilitarlo una vez para tu usuario (persiste; es el default
# recomendado por Microsoft para desarrollo: exige firma solo en scripts
# descargados de internet, no en los locales)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Interfaz grafica

`Gui.ps1` es una ventana WinForms con:
- Checkboxes para activar/desactivar servicios, red, prioridad agresiva, y
  si se espera a que abras el juego para ajustar su prioridad de proceso.
- Botones **Optimizar** / **Restaurar** que corren los scripts en segundo
  plano mientras el log se muestra en vivo en la ventana.
- Botones para el flujo de medicion: **Descargar PresentMon**, **Medir
  'Antes'**, **Medir 'Despues'**, **Comparar resultados**.
- Un indicador de estado arriba (OPTIMIZADO / sin optimizar) segun exista o
  no `state\backup.json`.

## Uso por linea de comandos

```powershell
# 1. Aplicar optimizaciones (como Administrador)
.\Optimize-LoL.ps1

# 2. Jugar

# 3. Revertir TODO al estado original cuando termines
.\Restore-LoL.ps1
```

Parametros utiles de `Optimize-LoL.ps1`:

| Parametro | Efecto |
|---|---|
| `-SkipServices` | No pausar SysMain/DiagTrack |
| `-SkipNetwork` | No tocar Nagle ni QoS |
| `-SkipQos` | Aplicar Nagle pero no crear la politica de QoS |
| `-SkipProcessWait` | No esperar a que abras el juego para ajustar su prioridad |
| `-Aggressive` | Prioridad de proceso `High` en vez de `AboveNormal` |

Todo lo que se modifica queda registrado en `state\backup.json`. **Nunca
edites ese archivo a mano** — `Restore-LoL.ps1` lo usa para saber
exactamente que revertir.

## Medir si realmente mejoro (antes/despues)

Esto es lo que responde la pregunta "¿de verdad se siente mejor, o es
placebo?", usando [PresentMon](https://github.com/GameTechDev/PresentMon)
(herramienta open-source estandar de la industria, la misma que usan
benchmarks como CapFrameX) para capturar frame time real durante la partida.

```powershell
# Una sola vez: descargar PresentMon
.\benchmark\Get-PresentMon.ps1

# ANTES de optimizar: juega una partida con esto corriendo
.\benchmark\Measure-Session.ps1 -Label antes

# Aplica las optimizaciones
.\Optimize-LoL.ps1

# DESPUES: juega otra partida (idealmente similar: mismo campeon/mapa/duracion)
.\benchmark\Measure-Session.ps1 -Label despues

# Compara ambas capturas
.\benchmark\Compare-Sessions.ps1
```

`Compare-Sessions.ps1` reporta FPS promedio, **1% low** y **0.1% low** (los
frames mas lentos — lo que realmente se siente como tiron) y el **jitter**
(variabilidad del frame time). El veredicto se basa principalmente en el 1%
low y el jitter, no solo en el FPS promedio, porque el promedio puede subir
sin que los tirones desaparezcan.

Para una comparacion valida: juega partidas de duracion y contenido
similares (evita comparar una partida tranquila de lane phase contra un
teamfight de 5v5), y con las mismas apps de fondo abiertas en ambas
capturas.

## Estructura del proyecto

```
install.ps1              Bootstrap para 'irm | iex': descarga el repo y abre Gui.ps1
Gui.ps1                   Interfaz grafica (WinForms), se autoeleva a Administrador
Iniciar-Optimizador.cmd  Lanzador de doble clic para Gui.ps1 (sin lios de politica de ejecucion)
Optimize-LoL.ps1        Aplica todos los ajustes (requiere Administrador)
Restore-LoL.ps1          Revierte todo usando state\backup.json
modules/
  Common.psm1             Logging + sistema de respaldo/restauracion generico
  SystemTweaks.psm1        Energia, MMCSS, Game DVR, servicios, prioridad de proceso
  NetworkTweaks.psm1       Nagle, QoS
  GpuTweaks.psm1            Preferencia de GPU dedicada
  LolConfig.psm1            Deteccion de instalacion + checklist de graficos
benchmark/
  Get-PresentMon.ps1        Descarga PresentMon (release oficial)
  Measure-Session.ps1       Captura una sesion de juego a CSV
  Compare-Sessions.ps1      Compara antes/despues y da un veredicto
state/                     Respaldo de configuracion original (gitignored)
logs/                      Capturas CSV y reportes (gitignored)
tools/                     Binario de PresentMon descargado (gitignored)
```

## Seguridad y reversibilidad

- Cada valor de registro modificado guarda su valor original (o el hecho de
  que no existia) antes de cambiarlo.
- Los servicios se pausan (`Manual`), nunca se deshabilitan permanentemente.
- `Restore-LoL.ps1` es idempotente: si no hay nada que restaurar, no hace
  nada.
- Ningun script requiere deshabilitar Windows Defender, UAC, ni ningun
  mecanismo de seguridad del sistema.
