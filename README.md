# Tarea 2 — Taller de Redes: Protocolo RTMP
> Despliegue en contenedores Docker de un servidor RTMP (Node-Media-Server) y clientes VLC que publican y reproducen video, con captura y análisis del tráfico generado.
> Video de la entrega: https://drive.google.com/file/d/1CuB4renYN_XXiC_4Zf2I5zjX3ak_Ib-_/view?usp=sharing

## Tabla de contenidos
* [Información general](#información-general)
* [Tecnologías utilizadas](#tecnologías-utilizadas)
* [Funcionalidades](#funcionalidades)
* [Capturas de pantalla](#capturas-de-pantalla)
* [Instalación](#instalación)
* [Uso](#uso)
* [Tipos de tráfico identificados](#tipos-de-tráfico-identificados)
* [Pruebas de parámetros](#pruebas-de-parámetros)
* [Seguridad](#seguridad)
* [Estado del proyecto](#estado-del-proyecto)
* [Mejoras pendientes](#mejoras-pendientes)
* [Agradecimientos](#agradecimientos)


## Información general
- Trabajo Taller de Redes y Servicios. El protocolo asignado es **RTMP** (_Real-Time Messaging Protocol_).
- El objetivo es instalar una dupla servidor–cliente que use RTMP, ponerla a comunicarse y estudiar el tráfico que genera: el handshake, los comandos AMF0, los mensajes de control y el flujo de audio y video.
- Toda la experiencia corre en contenedores para que se pueda repetir en cualquier equipo con un solo `docker compose`.
- Este repositorio es la base de la Tarea 3, donde se modificará el tráfico en tránsito y se medirán sus efectos.


| Rol | Software | Repositorio |
|---|---|---|
| Servidor | Node-Media-Server v4.4.6 | https://github.com/illuspas/Node-Media-Server |
| Cliente (publicador y reproductor) | VLC 3.0.x | https://github.com/videolan/vlc |

Arquitectura (red bridge `rtmpnet`, 172.28.0.0/24):

```
 vlc-publisher (172.28.0.20) --RTMP publish--> nms (172.28.0.10:1935) --RTMP play--> vlc-player (172.28.0.30)
                                                  ^
                                         sniffer (tcpdump, misma interfaz que nms)
```


## Tecnologías utilizadas
- Docker Engine 29.9.3 y Docker Compose v5.7.0
- Node.js 22 (imagen `node:22-alpine`)
- Node-Media-Server 4.4.6
- VLC 3.0 (imagen `debian:bookworm-slim`)
- tcpdump (imagen `nicolaka/netshoot`)
- Wireshark / tshark 4.6.4
- FFmpeg (solo para generar el video de prueba)


## Funcionalidades
- Servidor RTMP en el puerto 1935, con panel web y API en el puerto 8000.
- VLC como **publicador**: remultiplexa un MP4 (H.264 + AAC) a FLV y lo envía por RTMP, sin recodificar.
- VLC como **reproductor**, con ventana (`player-gui`) o sin ella (`player`, útil para capturas repetibles).
- **Sniffer** que comparte la interfaz del servidor y guarda todo el tráfico RTMP en `captures/rtmp_docker.pcap`.
- Pruebas de modificación de parámetros: autenticación con firma, RTMPS y cambio de bitrate (perfil `pruebas`).
- Script `scripts/analizar_rtmp.sh` que resume una captura con tshark: conversaciones, mensajes de control, tipos de cabecera de chunk, keyframes y cierres.


## Capturas de pantalla
Arranque de los contenedores y log del servidor:
![docker compose ps y logs de NMS](./informe/captura_compose.png)

Inicio de la sesión de publicación en Wireshark (filtro `rtmpt`):
![Wireshark: handshake y comandos](./informe/captura_wireshark_lista.png)

Comando `connect('live')` desplegado:
![Wireshark: connect](./informe/captura_connect.png)

Carga útil TCP por segundo en cada sentido:
![Throughput](./informe/throughput.png)

VLC en contenedor reproduciendo el flujo:
![VLC reproduciendo rtmp://nms:1935/live/test](./informe/captura_vlc.png)

Panel web de Node-Media-Server con el flujo activo:
![Panel /admin](./informe/captura_admin.png)


## Instalación
Requisitos:
- Ubuntu (probado en Ubuntu 26.04.1 LTS en máquina virtual), con 4 GB de RAM y 2 CPU como mínimo.
- Docker Engine con el plugin `docker compose`.
- Wireshark/tshark, git y, opcionalmente, ffmpeg.

```bash
# Herramientas
sudo apt update
sudo apt install -y wireshark tshark ffmpeg git x11-xserver-utils

# Docker: seguir https://docs.docker.com/engine/install/ubuntu/ y luego
sudo usermod -aG docker $USER      # cerrar sesión y volver a entrar

# Proyecto
git clone https://github.com/csanmartin12/Tarea2_RTMP.git
cd Tarea2_RTMP
chmod +x scripts/*.sh
docker compose build
```

Opcional: regenerar el video de prueba de 3 minutos incluido en `media/`.

```bash
ffmpeg -y -f lavfi -i testsrc=size=640x360:rate=25 -f lavfi -i sine=frequency=440:sample_rate=44100 \
  -t 180 -pix_fmt yuv420p -c:v libx264 -preset veryfast -g 50 -b:v 600k -c:a aac -b:a 96k media/muestra.mp4
```


## Uso
**1. Levantar el servidor y la captura**
```bash
docker compose up -d nms sniffer
docker compose logs nms        # "Rtmp Server listening on port 0.0.0.0:1935"
```

**2. Publicar el video con VLC** (otra terminal)
```bash
docker compose up publisher
```

**3. Reproducir con VLC** (otra terminal, mientras se publica)
```bash
xhost +local:
docker compose --profile gui up player-gui        # con ventana
# o bien
docker compose --profile headless up player       # sin ventana
```
También funciona desde el VLC del host: *Medio → Abrir ubicación de red →* `rtmp://localhost:1935/live/test`.

**4. Panel web**

Abrir http://localhost:8000/admin (usuario `admin`, contraseña `admin`) y ver la sección *Streams*.

**5. Detener y analizar**
```bash
docker compose logs nms > captures/nms.log
docker compose --profile gui --profile headless down
sudo chown -R $USER:$USER captures
./scripts/analizar_rtmp.sh captures/rtmp_docker.pcap
wireshark captures/rtmp_docker.pcap
```

> **Importante para Wireshark:** el filtro de visualización es `rtmpt` (con t); `rtmp` es otro protocolo (AppleTalk) y no muestra nada. En Wireshark 4.2 o anterior, además, hay que subir *Edit → Preferences → Protocols → RTMPT → Maximum packet size* a `2000000`, porque Node-Media-Server usa un _chunk size_ de 65535 bytes y el disector descarta mensajes mayores a 32768 (aparecen como *Malformed*). En la versión 4.6 esa opción ya no existe ni hace falta.

Estructura del repositorio:
```
docker-compose.yml     servidor, publicador, reproductor, sniffer y servicios de prueba
docker-compose.auth.yml  variante del servidor con autenticación (prueba A)
server/                Dockerfile, config.json y config.auth.json de Node-Media-Server
vlc/                   Dockerfile de VLC (publicador y reproductor)
media/muestra.mp4      video de prueba (H.264 640x360 25 fps + AAC 44.1 kHz)
scripts/               analizar_rtmp.sh, firmar.sh, prueba_nativa.sh (sin Docker)
captures/              capturas .pcap y resúmenes
informe/               informe en Typst (main.typ) e imágenes
```


## Tipos de tráfico identificados
P = publicador `172.28.0.20:56514`, S = servidor `172.28.0.10:1935`, R = reproductor `172.28.0.30:40932` (tramas de `captures/rtmp_docker.pcap`).

| # | Tipo | Type id | Trama | Origen → Destino |
|---|---|---|---|---|
| 1 | Handshake C0+C1 / S0+S1+S2 / C2 | — | 4, 6, 8 | P → S, S → P |
| 2 | Comando `connect` | 0x14 | 12 | P → S |
| 3 | Window Acknowledgement Size | 0x05 | 14 | S → P |
| 4 | Set Peer Bandwidth | 0x06 | 16 | S → P |
| 5 | Set Chunk Size | 0x01 | 16, 20 | S → P, P → S |
| 6 | `createStream` / `publish` / `play` / `deleteStream` | 0x14 | 20, 25, 5847, 48165 | P → S, R → S |
| 7 | Respuestas `_result` / `onStatus` | 0x14 | 22, 27, 5850 | S → P, S → R |
| 8 | Metadatos `@setDataFrame(onMetaData)` | 0x12 | 30, 5850 | P → S, S → R |
| 9 | Audio Data (AAC) | 0x08 | 30 en adelante | P → S, S → R |
| 10 | Video Data (H.264) | 0x09 | 30 en adelante | P → S, S → R |
| 11 | User Control: Stream Begin / Set Buffer Length | 0x04 | 5849, 5847 | S → R, R → S |
| 12 | Acknowledgement | 0x03 | 15348 | R → S |


## Pruebas de parámetros
Usan el perfil `pruebas` del `docker-compose.yml`. Para capturar su tráfico (RTMP y RTMPS) en `captures/pruebas.pcap`:
```bash
docker compose --profile pruebas up -d sniffer-pruebas
```

**A. Autenticación con firma (servidor).** `server/config.auth.json` activa `auth.publish`, `auth.play` y el `secret` `tallerredes2026`.
```bash
docker compose down
docker compose -f docker-compose.yml -f docker-compose.auth.yml up -d nms
docker compose --profile pruebas up publisher-firma      # SIN firma: el servidor la rechaza (Ctrl+C para salir)
export SIGN=$(./scripts/firmar.sh /live/test)            # firma válida por 1 hora
docker compose --profile pruebas up publisher-firma      # CON firma: se acepta
docker compose --profile pruebas up player-firma         # (en otra terminal, mientras se publica)
docker compose logs nms | grep -E "push|play|authentication"
```

**B. RTMPS (servidor).** Publica por TLS en el puerto 1936; en Wireshark sólo se ve tráfico cifrado.
```bash
docker compose down && docker compose up -d nms
docker compose --profile pruebas up -d sniffer-pruebas
docker compose --profile pruebas up publisher-rtmps
```

**C. Bitrate (cliente).** VLC recodifica a 300 kbit/s de video y 64 kbit/s de audio en lugar de remultiplexar.
```bash
docker compose --profile pruebas up publisher-300k
```

| Prueba | Resultado |
|---|---|
| A sin firma | `authentication verification failed` (publicación y reproducción rechazadas) |
| A con firma | publicación y reproducción aceptadas |
| B RTMPS | TLS 1.3 (`TLS_AES_256_GCM_SHA384`); la ruta `live/test` no aparece en la captura |
| C 300k | la subida baja de ≈ 607 a ≈ 221 kbit/s; _keyframe_ cada 10 s en vez de 2 s |


## Seguridad
Con la configuración por defecto el despliegue tiene cinco problemas, analizados en el informe:
1. RTMP viaja **sin cifrar**: la clave del flujo y los comandos se leen en Wireshark → usar RTMPS (prueba B).
2. **Sin autenticación** de publicación ni reproducción → activar `auth` (prueba A).
3. La **firma viaja en claro** y se puede reutilizar mientras no expire → firmas cortas y siempre sobre RTMPS.
4. **Sin integridad**: un intermediario puede modificar mensajes en tránsito → TLS.
5. **Denegación de servicio**: el servidor acepta `play` sobre flujos inexistentes y deja la conexión abierta; además el panel web (puerto 8000) usa HTTP y credenciales simples (`admin`/`admin`).

> Las credenciales de `server/config.json` (`admin`/`admin` y el `jwt.secret`) son sólo para este laboratorio. No uses esta configuración en una red real.


## Estado del proyecto
Proyecto: _en progreso_. Completos los capítulos 1 (Introducción al protocolo) y 2 (Análisis de tráfico), entregados en la Tarea 2. El capítulo 3 (Modificación de tráfico y análisis de métricas) se desarrollará en la Tarea 3.


## Mejoras pendientes
Mejoras:
- Publicar en bucle para tener una transmisión continua.
- Usar RTMPS y autenticación por defecto en vez de dejarlos como prueba opcional.

Pendiente (Tarea 3):
- Interceptar y modificar campos RTMP en tránsito (_chunk size_, _type id_, timestamps, comandos AMF0).
- Medir latencia, throughput y pérdida bajo distintas condiciones de red (`tc netem`).


## Agradecimientos
- Especificación _Adobe's Real Time Messaging Protocol_ v1.0 (2012).
- Documentación de [Node-Media-Server](https://github.com/illuspas/Node-Media-Server) y [VLC](https://github.com/videolan/vlc).



