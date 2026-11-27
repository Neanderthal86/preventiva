<p align="center">
  <img src="assets/TF-Toolkit.svg" width="96" height="96" alt="Icono de TF-Toolkit: un yunque blanco con la cara naranja">
</p>

# TF-Toolkit

[![Versión más reciente](https://img.shields.io/github/v/release/guilhermehenn/tf-toolkit?label=versi%C3%B3n)](https://github.com/guilhermehenn/tf-toolkit/releases/latest)
[![Licencia GPLv3](https://img.shields.io/badge/licencia-GPLv3-blue)](LICENSE)
[![Windows 10 y 11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4)](#requisitos)
[![Windows PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE)](#requisitos)

[Português](README.md) · [English](README.en.md) · **Español**

Cuida tu PC con Windows en un solo lugar: TF-Toolkit limpia, repara, actualiza y avisa antes del problema, en una ventana sencilla o, si lo prefieres, en un menú en el terminal. Pregunta antes de lo que tiene peso y guarda cómo estaban las cosas, para que puedas volver atrás.

[Sitio web](https://usewinforge.com.br/es/) · [**Descargar TF-Toolkit**](https://github.com/guilhermehenn/tf-toolkit/releases/latest/download/TF-Toolkit.zip) · [Todas las versiones](https://github.com/guilhermehenn/tf-toolkit/releases) · [Qué cambió (en portugués)](CHANGELOG.md)

<p align="center">
  <img src="https://raw.githubusercontent.com/guilhermehenn/tf-toolkit/main/docs/images/inicio.png" width="820" alt="La pantalla Inicio de TF-Toolkit, con la nota de salud del PC y los botones Revisar el PC y Optimizar">
</p>

## Por qué TF-Toolkit

- **Todo en un solo lugar:** limpieza, reparación de Windows, actualizaciones, red, seguridad, programas y ajustes, en cuatro grupos: Cuidar, Reparar, Proteger y Configurar.
- **Sin sustos:** lo que borra o toca a fondo el sistema pregunta antes. Cada ajuste guarda el valor original, y **Optimizar** empieza por un punto de restauración.
- **Avisa antes del problema:** un icono junto al reloj, opcional, avisa cuando el disco se llena o da señales de falla, la protección se desactiva o falta mantenimiento.
- **Usa las herramientas de Windows:** Windows Update, Microsoft Defender, DISM, SFC, CHKDSK y winget, sin "aceleradores" de otras empresas.
- **Tus datos se quedan en tu PC:** sin cuenta y sin telemetría.

## Empezar

1. Descarga **TF-Toolkit.zip** y extrae la carpeta completa (clic derecho > **Extraer todo**).
2. Abre **TF-Toolkit-Setup.cmd** y acepta el aviso de administrador de Windows. TF-Toolkit queda en el menú Inicio y en **Configuración > Aplicaciones**.
3. Abre TF-Toolkit. En el **Inicio**, la nota de salud dice cómo está el PC, y dos botones se encargan del resto:
   - **Revisar el PC** revisa el PC en 11 pasos y corrige con un clic lo que es seguro;
   - **Optimizar** hace el mantenimiento completo en 20 pasos: las preguntas vienen al principio y después sigue solo. Puede tardar más de una hora.

¿Prefieres no instalarlo? Abre **TF-Toolkit.cmd** directamente desde la carpeta extraída.

## Lo que hace

| Grupo | Páginas | Por ejemplo |
|---|---|---|
| **Cuidar** | Mantenimiento, Limpieza, Rendimiento | Limpieza rápida, análisis del espacio, archivos duplicados, lo que se abre con Windows, mantenimiento programado |
| **Reparar** | Reparación, Diagnóstico, Red | Reparar Windows (DISM + SFC), CHKDSK, pantallas azules con la causa probable, prueba de memoria, salud de los discos, reparación de la red y del DNS, la impresión atascada |
| **Proteger** | Seguridad, Actualizaciones | Estado de la protección, auditoría de seguridad, clave de recuperación de BitLocker, actualizaciones de Windows, controladores y programas |
| **Configurar** | Programas, Ajustes de Windows, Personalización | Instalar y desinstalar programas, copia antes de formatear, 53 ajustes de Windows con perfiles listos |

Y además:

- **Monitor en la bandeja** (opcional): avisa antes del problema, y el clic en el aviso abre la acción correcta.
- **Historial de cambios** (en Mantenimiento): lo que TF-Toolkit cambió en el PC, con la opción de deshacer lo que tiene vuelta atrás.
- **Tres idiomas:** portugués, inglés y español, siguiendo el idioma de Windows (se elige en **Acerca de TF-Toolkit > Idioma**).

## Requisitos

- Windows 10 u 11, con el Windows PowerShell 5.1 que ya trae.
- Permisos de administrador para buena parte de las acciones. TF-Toolkit los pide al abrir; sin ellos, se abre igual y los vuelve a pedir cuando una acción los necesita.
- El Instalador de aplicación (winget) para instalar, actualizar y desinstalar programas. Viene con Windows; si falta, TF-Toolkit ofrece repararlo.
- Internet solo para lo que depende de ella: las actualizaciones, los programas, las pruebas de red y la búsqueda de una versión nueva.

## Seguridad y privacidad

> [!IMPORTANT]
> Los scripts no tienen firma digital, y Windows puede avisar al abrirlos. Descarga solo desde la [página de versiones](https://github.com/guilhermehenn/tf-toolkit/releases) y, si quieres, comprueba el zip en PowerShell: el resultado debe ser igual al SHA-256 publicado en la página de la versión.
>
> ```powershell
> Get-FileHash .\TF-Toolkit.zip -Algorithm SHA256
> ```

- **No se envía nada de tu PC.** TF-Toolkit solo se conecta a internet para buscar una versión nueva y descargar la lista de programas y las fechas de soporte de Windows (desde GitHub), y en las pruebas de red que pides (velocidad, conectividad e IP pública). Lo demás pasa por las herramientas de Windows y de cada programa: Windows Update, Microsoft Defender, winget, Microsoft Store y los actualizadores de los navegadores.
- **No todo tiene vuelta atrás:** lo que la limpieza borra y los programas desinstalados no vuelven por TF-Toolkit. Por eso pregunta antes.
- **Los datos de TF-Toolkit** (registros, informes e historiales) se guardan en `%LOCALAPPDATA%\TF-Toolkit`. La copia antes de formatear no copia tus archivos personales y guarda las contraseñas del Wi-Fi en texto: protege la copia.

## Actualizar y desinstalar

- **Actualizar:** **Acerca de TF-Toolkit > Buscar una versión nueva** descarga la versión nueva, comprueba su SHA-256 y la instala con un clic; TF-Toolkit se cierra y se abre de nuevo ya actualizado. Si algo falla a mitad de camino, vuelven los archivos anteriores. Con el monitor en la bandeja activado, TF-Toolkit avisa cuando sale una versión nueva. Vale desde la 4.0: desde una versión anterior, instala la 4.0 con **TF-Toolkit-Setup.cmd**.
- **Desinstalar:** desde **Configuración > Aplicaciones**, o abriendo **TF-Toolkit-Setup.cmd** en la carpeta instalada. Pregunta si también borra los datos de `%LOCALAPPDATA%\TF-Toolkit`. Los ajustes de Windows se quedan como están: para volver a como estaban, usa antes **Ajustes de Windows > Deshacer ajustes de TF-Toolkit**.

## Línea de comandos

```powershell
.\TF-Toolkit-Console.cmd                      # menú en el terminal
.\TF-Toolkit-Console.cmd -Action Check -Json  # revisión rápida, en JSON
.\TF-Toolkit-Console.cmd -Action Report       # informe HTML y de texto
.\TF-Toolkit-Console.cmd -Language es         # pt, en o es
```

La revisión rápida no pide permisos de administrador y da el resultado en el código de salida: 0 todo al día, 1 puntos de atención, 2 algo crítico, 3 no se pudo evaluar.

## Preguntas frecuentes

<details>
<summary><strong>¿TF-Toolkit hace el PC más rápido?</strong></summary>

Quita lo que pesa sin necesidad (archivos temporales, lo que se abre con Windows, programas que pesan ahora), repara Windows y mantiene todo al día. No promete una cifra de velocidad: la mejora depende de cómo estaba el PC.
</details>

<details>
<summary><strong>¿Sustituye al antivirus?</strong></summary>

No. La seguridad de TF-Toolkit usa el Microsoft Defender del propio Windows: revisa la protección, actualiza las firmas y hace el análisis. Con otro antivirus instalado, las acciones de Defender quedan fuera.
</details>

<details>
<summary><strong>Cambió algo que no quería. ¿Cómo vuelvo atrás?</strong></summary>

En **Mantenimiento > Historial de cambios**, cada cambio que tiene vuelta atrás tiene su opción de deshacer. Para todos los ajustes de Windows a la vez, **Ajustes de Windows > Deshacer ajustes de TF-Toolkit**. Y el punto de restauración que Optimizar crea al principio devuelve el sistema con Restaurar sistema de Windows.
</details>

<details>
<summary><strong>¿Funciona sin internet?</strong></summary>

La limpieza, el diagnóstico, los ajustes y buena parte de las reparaciones, sí. Las actualizaciones, los programas, las pruebas de red y la búsqueda de una versión nueva necesitan internet.
</details>

<details>
<summary><strong>¿Por qué pide permisos de administrador?</strong></summary>

Reparar Windows, instalar actualizaciones y cambiar ajustes del sistema los necesitan. Si los rechazas, TF-Toolkit se abre igual, y las acciones que los necesitan muestran el escudo y los vuelven a pedir.
</details>

## Ayuda

¿Encontraste un problema o tienes una sugerencia? [Abre un issue](https://github.com/guilhermehenn/tf-toolkit/issues/new). Para ayudar a investigar un problema, incluye:

- La versión de TF-Toolkit y la versión y compilación de Windows.
- La interfaz utilizada: ventana o terminal.
- La función ejecutada y los pasos para reproducir el problema.
- El resultado esperado y lo que ocurrió.
- El mensaje de error completo o una captura de pantalla.

**Acerca de TF-Toolkit > Paquete de soporte** reúne los registros, la revisión rápida y el último informe en un zip. Antes de compartir registros, informes o el paquete, revisa su contenido y elimina la información personal.

**¿Encontraste un fallo de seguridad?** No abras un issue público: sigue la [política de seguridad](https://github.com/guilhermehenn/tf-toolkit/security/policy) y usa **Report a vulnerability**, que solo ve el mantenedor.

## Para desarrolladores

- [Documentación técnica (en portugués)](https://github.com/guilhermehenn/tf-toolkit/blob/main/docs/documentacao-tecnica-4.0.md): cómo está hecho TF-Toolkit, dónde está cada cosa y cómo cambiar el código. Quien llega ahora empieza por "Comece por aqui" (empieza aquí).
- [Índice de la documentación (en portugués)](https://github.com/guilhermehenn/tf-toolkit/blob/main/docs/README.md): el mapa de funciones y la documentación técnica.
- `modules/`: las funciones; `gui/`: la ventana; `lang/`: las traducciones (gettext); `tools/`: firma, el zip de la versión y traducciones.
- [Qué cambió en cada versión (en portugués)](CHANGELOG.md) y la [guía detallada de la build 3.69](https://github.com/guilhermehenn/tf-toolkit/blob/v3.69.0/README.md) (archivada, en portugués).

## Licencia

[GNU GPLv3](LICENSE) · © 2026 [Guilherme Henn](https://github.com/guilhermehenn), que mantiene TF-Toolkit.
