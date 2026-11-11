# Cliente RTMP: VLC (https://github.com/videolan/vlc)
# La misma imagen se usa como publicador (sout -> rtmp://) y como reproductor (rtmp:// -> pantalla).
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        vlc-bin vlc-plugin-base vlc-plugin-video-output vlc-plugin-qt \
        ca-certificates iproute2 iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# VLC se niega a ejecutarse como root
RUN useradd -m -u 1000 vlcuser \
    && mkdir -p /tmp/runtime-vlcuser && chown vlcuser:vlcuser /tmp/runtime-vlcuser \
    && chmod 700 /tmp/runtime-vlcuser
USER vlcuser
WORKDIR /home/vlcuser

# Evita el aviso "XDG_RUNTIME_DIR not set" de Qt/VLC
ENV XDG_RUNTIME_DIR=/tmp/runtime-vlcuser

ENTRYPOINT ["cvlc"]
