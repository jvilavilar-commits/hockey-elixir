# Neon Rink — hockey 2D multijugador en Elixir

Videojuego 2 vs 2 con vista superior, física en tiempo real y servidor
autoritativo. La partida empieza al conectarse cuatro jugadores, dura tres
minutos, se pausa si alguien pierde la conexión y permite iniciar una revancha
al terminar.

## Características

- Cuatro jugadores humanos: puestos 1–2 en el equipo azul y 3–4 en el rojo.
- Movimiento con `WASD` o flechas y golpe con la barra espaciadora.
- Colisiones jugador–jugador, jugador–disco y disco–pared con rebote.
- Goles, marcador en vivo, reloj de 3:00 y recolocación tras cada gol.
- Estado oficial calculado a 60 ticks por segundo en Elixir.
- Instantáneas enviadas por WebSocket unas 20 veces por segundo.
- Pausa automática y reconexión al mismo puesto mediante un token de sesión.
- Resultado final, empate permitido y botón de revancha.
- Interfaz Canvas adaptable a escritorio, tableta y móvil.

## Inicio rápido con Docker

Solo se necesita Docker con Compose:

```bash
docker compose up --build
```

Abrir <http://localhost:4000>. Para detener el servidor:

```bash
docker compose down
```

## Ejecución local con Mix

Requisitos: Elixir 1.17 o superior y OTP 27 o superior.

```bash
mix deps.get
mix run --no-halt
```

El puerto predeterminado es `4000`. Puede cambiarse así:

```bash
PORT=8080 mix run --no-halt
```

El endpoint `GET /health` responde `ok` y puede utilizarse para comprobar que
el servidor está listo.

## Probar una partida con cuatro jugadores

1. Iniciar el servidor y abrir `http://localhost:4000` en cuatro pestañas o
   ventanas. También pueden usarse cuatro navegadores o equipos de la misma red.
2. Cada cliente recibe automáticamente un puesto. Los dos primeros son azules;
   los dos siguientes, rojos.
3. Cuando el contador muestra `4 / 4`, la partida comienza sin intervención.
4. Hacer clic en cada pestaña antes de usar sus controles. Mover con `WASD` o
   flechas y pulsar espacio cerca del disco para golpearlo.
5. Cerrar o recargar una pestaña durante la partida. Los otros clientes deben
   mostrar la pausa; al volver a abrirla, el token guardado en `sessionStorage`
   recupera el mismo puesto y la partida continúa.
6. Al terminar el reloj, pulsar **Jugar de nuevo** para reiniciar marcador,
   tiempo y posiciones.

Para probar desde otros equipos de la red local, abrir
`http://IP_DEL_SERVIDOR:4000` y permitir el puerto 4000 en el firewall si fuera
necesario.

## Arquitectura

```text
Navegador (Canvas + controles)
          │  WebSocket JSON
          ▼
HockeyWeb.Socket ── mensajes ──► Hockey.PlayerServer (uno por jugador)
                                      │
                                      │ GenServer.cast
                                      ▼
                               Hockey.GameServer
                               estado autoritativo
                                      │
                         funciones puras por cada tick
                                      ▼
                         Hockey.Game + Hockey.Physics
```

- `Hockey.GameServer`: actor principal de la sala. Mantiene el único estado
  oficial, programa ticks, supervisa conexiones y transmite instantáneas.
- `Hockey.PlayerServer`: proceso ligero individual. Sanea la entrada de su
  cliente y la comunica al actor de partida mediante paso de mensajes.
- `Hockey.Game`: estructura y transiciones inmutables de partida: fases,
  reloj, puntuación, desconexiones y revancha.
- `Hockey.Physics`: funciones puras para movimiento, impulsos, colisiones,
  rebotes, límites, detección de goles y reinicio de posiciones.
- `HockeyWeb.Socket`: protocolo WebSocket; no decide posiciones ni resultados.
- `HockeyWeb.Router`: sirve la interfaz, `/socket` y `/health` mediante Bandit.
- `priv/static`: Canvas, presentación, controles, interpolación visual y estado
  de conexión. JavaScript nunca modifica el estado autoritativo.

La supervisión OTP usa un `DynamicSupervisor` para los jugadores y un
`GameServer` independiente. Todas las reglas trabajan sobre mapas y tuplas
inmutables y devuelven un estado nuevo.

## Protocolo WebSocket

El cliente envía entradas de esta forma:

```json
{"type":"input","input":{"up":false,"down":false,"left":false,"right":true,"kick":false}}
```

El servidor responde con `welcome` al asignar el puesto y después difunde
mensajes `state` con jugadores, disco, marcador, tiempo y fase. La acción
`{"type":"rematch"}` reinicia una partida finalizada si los cuatro puestos
siguen conectados.

## Pruebas

Ejecutar la suite completa:

```bash
mix test
```

Comprobar además formato y pruebas:

```bash
mix quality
```

La suite cubre:

- inicio al cuarto jugador;
- movimiento inmutable y límites;
- goles, marcador y recolocación;
- fin del reloj, ganador y empate;
- pausa sin avance del tiempo y reanudación;
- revancha;
- rebote, separación de jugadores y golpe al disco;
- cuatro procesos cliente, rechazo del quinto y reconexión por token;
- rutas HTTP de interfaz y salud.

En la verificación de entrega se compilaron todos los módulos y se ejecutaron
11 pruebas con 0 fallos. También se validó la sintaxis del JavaScript con Node.

## Decisiones y límites intencionales

- Existe una sola sala de cuatro puestos, como solicita la primera versión.
- El estado vive en memoria; reiniciar el servidor reinicia la sala.
- Un puesto desconectado durante una partida permanece reservado a su token. Es
  una decisión deliberada para que otro usuario no suplante al jugador ausente.
- No hay cuentas, bots, chat, clasificación ni persistencia, porque quedan fuera
  del alcance definido.
