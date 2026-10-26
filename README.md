# fotos

CLI para macOS que imprime fotos en tamaño estándar (4x6, 5x7, 3.5x5, 5x5, 8x10) **sin bordes**, pensado para impresoras Canon PIXMA vía AirPrint (probado con la Canon G500).

## Qué hace

1. Lee cada foto respetando su orientación EXIF.
2. Gira las fotos horizontales para que llenen la hoja vertical.
3. **Recorte inteligente**: detecta caras y personas con el framework Vision de Apple y acomoda el recorte para no cortar cabezas. Si no cabe todo, prioriza las cabezas y sacrifica los pies.
4. Genera un PDF con el tamaño de página exacto (p. ej. 4x6 = 288×432 pt), una foto por página.
5. Genera una hoja de contacto (`vista-previa.png`) para revisar los recortes.
6. Lo manda con `lp` usando el tamaño `*.Fullbleed` y el tipo de papel indicado.

¿Por qué PDF de tamaño exacto? Mandar JPEGs con `fit-to-page` por AirPrint a la G500 sacaba hojas en blanco; el PDF a la medida imprime bien.

## Instalar

Requiere macOS 12+ y las herramientas de línea de comandos de Xcode (`swiftc`).

```sh
swiftc -O fotos.swift -o ~/.local/bin/fotos
```

## Uso

```sh
# Revisar primero (no imprime, abre la vista previa)
fotos --preview ~/Downloads/fotos/*.jpg

# Imprimir en 4x6, papel Canon Photo Paper Plus Glossy II
fotos ~/Downloads/fotos/*.jpg

# Otras opciones
fotos --size 5x7 --paper matte --printer Canon_G500_series foto.jpg
```

| Opción | Valores | Default |
|---|---|---|
| `--size` | `4x6` `5x7` `3.5x5` `5x5` `8x10` | `4x6` |
| `--paper` | `glossy2` `glossy` `matte` `plain` | `glossy2` |
| `--preview` | — | imprime |
| `--printer` | nombre de la cola (`lpstat -p`) | predeterminada |
| `--out` | carpeta para PDF y vista previa | temporal |

## Si la impresora dice "tamaño de papel diferente"

Las Canon comparan el trabajo con el papel registrado al cargar la bandeja. Al cargar papel 4x6, regístralo como 10x15 cm en la pantalla de la impresora, o desactiva *Detectar falta de coincidencia del papel* en la configuración del dispositivo.

## Licencia

MIT
