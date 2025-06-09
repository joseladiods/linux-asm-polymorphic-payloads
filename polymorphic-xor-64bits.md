# Polimorfismo XOR de 64 bits   

Es una técnica sencilla para modificar el contenido binario de un programa en cada ejecución, manteniendo su funcionalidad intacta. En esencia, consiste en recorrer el código en bloques de 8 bytes (64 bits) y aplicarles a cada bloque la operación lógica XOR con una clave de 64 bits (un valor entre 1 y 2⁶⁴−1; no se utiliza 0 como clave en ninguno de los 8 bytes que conforman la clave, ya que XOR con 0 deja el byte sin cambios y, por tanto, no tendría efecto polimórfico). Dado que XOR es reversible, basta con volver a aplicar la misma clave para restaurar el contenido original antes de ejecutarlo.

Este enfoque ofrece ventajas significativas sobre implementaciones de 8 bits: el procesamiento en bloques de 8 bytes puede incrementar hasta 8 veces la velocidad teórica en los bucles de cifrado/descifrado (especialmente notorio en archivos grandes), mientras que la robustez de la clave es exponencialmente superior, pasando de 255 posibles valores en el caso de 8 bits a 2⁶⁴−1 en la versión de 64 bits, haciendo prácticamente inviable un ataque de fuerza bruta.

De este modo, el archivo que contiene el payload nunca permanece *en claro*: tras cada ejecución, la huella de bytes cambia por completo, aunque el comportamiento en memoria —cuando se descifra con la clave correcta— permanece inalterado. Esta técnica proporciona un equilibrio entre simplicidad y efectividad para generar variantes constantes de un payload binario en disco y, al mismo tiempo, dificulta el análisis estático basado en firmas.

| Archivo | Descripción |
|---------|-------------|
| [`polymorphic-xor-64bits-payload-loader.asm`](./polymorphic-xor-64bits-payload-loader.asm) | Loader de payload contenido en un archivo cifrado con XOR: reserva dinámicamente memoria según el tamaño del payload, lee y descifra el contenido byte a byte, prepara los parámetros necesarios para el payload polimórfico (descriptor de archivo heredado, dirección base en memoria y tamaño) y lo ejecuta en memoria. |
| [`polymorphic-xor-64bits-nop-payload.asm`](./polymorphic-xor-64bits-nop-payload.asm) | Ejecuta su carga útil, en este caso un simple mensaje por STDOUT, y se **auto-cifra** con una clave de 64 bits [1, 2⁶⁴−1] que se genera en tiempo de ejecución y sobreescribe el archivo que lo contenía. Con esta metodología logramos que el archivo que contiene el payload vaya variando constantemente. |

### Preparación
      
Compilar el payload ( polymorphic-xor-64bits-nop-payload.asm )
```bash
> $ nasm -f bin polymorphic-xor-64bits-nop-payload.asm -o polymorphic-xor-64bits-nop-payload.bin
```
Agregarle al inicio del payload 8 bytes nulos, donde se almacenará la clave con el que se **auto-cifrará** el payload en cada ejecución. El archivo **payload-cipher.bin** es el que será referenciado por el **loader**.

```bash
> $ ( printf '\x00\x00\x00\x00\x00\x00\x00\x00'; cat polymorphic-xor-64bits-nop-payload.bin ) > payload-cipher.bin
```
Compilar y enlazar el loader ( polymorphic-xor-64bits-payload-loader.asm )
```bash
> $ nasm -f elf64 polymorphic-xor-64bits-payload-loader.asm -o polymorphic-xor-64bits-payload-loader.o

> $ ld polymorphic-xor-64bits-payload-loader.o -o polymorphic-xor-64bits-payload-loader
```
Hacemos un paréntesis y ejecutamos algunos procedimientos que nos van a permitir observar los cambios que se van produciendo en el **payload**.     

Las variables a considerar para el análisis son: salida de la ejecución, horario de modificación, tamaño, hash MD5 y volcado en formato hexadecimal.

#### Payload original
```bash
> $ ls -l --full-time polymorphic-xor-64bits-nop-payload.bin
-rw-rw-r-- 1 gmg gmg 296 2025-06-09 01:18:15.279497596 +0000 polymorphic-xor-64bits-nop-payload.bin
```
```bash
> $ md5sum polymorphic-xor-64bits-nop-payload.bin
18c3dadfff41d2f0167b3fd6051a276d  polymorphic-xor-64bits-nop-payload.bin
```
```bash
> $ hexdump -v -e '/1 "%02x"' polymorphic-xor-64bits-nop-payload.bin | tr -d '\n' ; echo
4889e04883e00f4829c44989f44989cd4989d64883ec08682121210a48b820506974686173655048b850726f796563746f504831c048ffc04889c74889e6ba140000000f054883c420480fc7f07302eb090f3148c1e2204809d04d31d284c0750348ffc048c1c80849ffc24983fa0875ec4889c34883ec104889042441bb03000000b8120000004c89e7488d3424ba080000004d31d20f054883f808740749ffcb745febdd4883c4104d31ff41bb030000004883ec104d39f77d394b8b443d004831d848890424b8120000004c89e7488d3424ba080000004983c7084d89fa0f054883f808740b49ffcb74274983ef08ebd5ebc24883c410b83c0000004831ff0f054883c410b83c0000004831ff48ffc70f054883c410b83c000000bf020000000f059090909090
```
#### Payload con el byte inicial agregado
```bash
> $ ls -l --full-time payload-cipher.bin
-rw-rw-r-- 1 gmg gmg 304 2025-06-09 01:18:29.951729984 +0000 payload-cipher.bin
```
```bash
> $ md5sum payload-cipher.bin
a0967e9b2ab7d9123e231eb77c16f6c0  payload-cipher.bin
```
```bash
> $ hexdump -v -e '/1 "%02x"' payload-cipher.bin | tr -d '\n' ; echo   
00000000000000004889e04883e00f4829c44989f44989cd4989d64883ec08682121210a48b820506974686173655048b850726f796563746f504831c048ffc04889c74889e6ba140000000f054883c420480fc7f07302eb090f3148c1e2204809d04d31d284c0750348ffc048c1c80849ffc24983fa0875ec4889c34883ec104889042441bb03000000b8120000004c89e7488d3424ba080000004d31d20f054883f808740749ffcb745febdd4883c4104d31ff41bb030000004883ec104d39f77d394b8b443d004831d848890424b8120000004c89e7488d3424ba080000004983c7084d89fa0f054883f808740b49ffcb74274983ef08ebd5ebc24883c410b83c0000004831ff0f054883c410b83c0000004831ff48ffc70f054883c410b83c000000bf020000000f059090909090
```

Observando las salidas, lo primero que notamos es que se produjo el incremento esperado de 8 bytes en el archivo (296 → 304 bytes).

Como el volcado hexadecimal muestra, la única diferencia está en los primeros 8 bytes (**00**00**00**00**00**00**00**00), y el MD5 distinto confirma que el archivo cambió.

Finalmente ejecutamos el **loader** por primera vez para que el **payload** se **auto-cifre** con una clave de 8 bytes en la que ninguno de sus bytes vale 0 (ya que hacer **XOR con 0** no altera el valor original).

#### Primera ejecución
```bash
> $ ./polymorphic-xor-64bits-payload-loader
Proyecto Pithase!!!

> $ ls -l --full-time payload-cipher.bin
-rw-rw-r-- 1 gmg gmg 304 2025-06-09 01:22:46.042835887 +0000 payload-cipher.bin

> $ md5sum payload-cipher.bin
046942faec6e40030b940650f466b6af  payload-cipher.bin

> $ hexdump -v -e '/1 "%02x"' payload-cipher.bin | tr -d '\n' ; echo
b4265ea0f67bb955fcafbee8759bb61d9de2172902323098fdaf88e87597b13d95077faabec39905dd5236c1851ee91d0c762ccf8f1eda21db76169136334695fcaf99e87f9d0341b4265eaff3333a91946e51670608bbbebd296fe83799991dbdf6139124ff7920b76ea160beba715dfdd99ce97581b120586ed763bef85545fcaf5a84b7c0ba55b426e6b2f67bb9193dc1162dc25f035db4265eedc7a9b650fca5a6a8827cf0aa7f52014b2b333a91a46b6f5fb7c0ba55b42616231a6bf46c435b67eb7d3f8455fc1786e87f7f9deda6265ea0baf25e1d39127a1afe7bb955fda599a8bbf2435ab16edd58fe0fb21c4bed2a87bff8565d5ff3b562bef87d450c1a5ea0f63388aabb231623326b0169b4265ee8c784f1aa73295be875bfa9ed88265ea04979b955b4295b3066eb29c5
```

Aquí ya podemos observar que los primeros 8 bytes —la clave— ya no son **(0000000000000000)**, sino **(b4265ea0f67bb955)** y el resto del programa es totalmente distinto, debido a que se encuentra cifrado con la nueva clave.

Con el transcurrir de las ejecuciones observamos que "la parte útil" del payload –el mensaje por pantalla– se ejecuta correctamente y a través de las variables de análisis confirmamos que las versiones del payload son siempre distintas.

#### Segunda ejecución
```bash
> $ ./polymorphic-xor-64bits-payload-loader
Proyecto Pithase!!!

> $ ls -l --full-time payload-cipher.bin
-rw-rw-r-- 1 gmg gmg 304 2025-06-09 01:26:08.812349474 +0000 payload-cipher.bin

> $ md5sum payload-cipher.bin
40e0ba248bdc0aa35ecd114d1573ea0d  payload-cipher.bin

> $ hexdump -v -e '/1 "%02x"' payload-cipher.bin | tr -d '\n' ; echo
132ec54e13b620885ba7250690562fc03aea8cc7e7ffa9455aa71306905a28e0320fe4445b0e00d87a5aad2f60d370c0ab7eb7216ad343fc7c7e8d7fd3fedf485ba702069a509a9c132ec54116fea34c3366ca89e3c522631a21f406d25400c01afe887fc132e0fd10663a8e5b77e8805ad10707904c28fdff664c8d5b35cc985ba7c16a520d2388132e7d5c13b620c49ac98dc327929a80132ec50322642f8d5bad3d4667b16977d85a9aa5cefea34c0363f4b1520d2388132e8dcdffa66db1e453fc0598f21d885b1f1d069ab20430012ec54e5f3fc7c09e1ae1f41bb620885aad02465e3fda87166646b61bc22bc1ece5b1695a35cf80f8fb2e8c5b35e498ab12c54e13fe11771c2b8dcdd7a698b4132ec50622496877d421c006907230302f2ec54eacb420881321c0de8326b018
```

#### Tercera ejecución
```bash
> $ ./polymorphic-xor-64bits-payload-loader
Proyecto Pithase!!!

> $ ls -l --full-time payload-cipher.bin
-rw-rw-r-- 1 gmg gmg 304 2025-06-09 01:27:26.684775781 +0000 payload-cipher.bin

> $ md5sum payload-cipher.bin
dea892df3986f625e05b8ff5061ac426  payload-cipher.bin

> $ hexdump -v -e '/1 "%02x"' payload-cipher.bin | tr -d '\n' ; echo
86cd9189374a2bcfce4471c1b4aa2487af09d800c303a202cf4447c1b4a623a7a7ecb0837ff20b9fefb9f9e8442f7b873e9de3e64e2f48bbe99dd9b8f702d40fce4456c1beac91db86cd91863202a80ba6859e4ec73929248fc2a0c1f6a80b878f1ddcb8e5ceebba85856e497f8be3c7cf3253c0b4b023ba6a85184a7fc9c7dfce4495ad76f128cf86cd299b374a2b830f2ad904036e91c786cd91c4069824cace4e6981434d62304db9ce62ea02a80b9680a07676f128cf86cdd90adb5a66f671b0a8c2bc0e16cfcefc49c1be4e0f7794cd91897bc3cc870bf9b5333f4a2bcfcf4e56817ac3d1c0838512713f3e20867906e5ae7ec9c4c76d187a4b7fc9efdf3ef1918937021a3089c8d90af35a93f386cd91c106b5633041c294c1b48e3b77bacd918988482bcf86c29419a7dabb5f
```

#### Cuarta ejecución
```bash
> $ ./polymorphic-xor-64bits-payload-loader
Proyecto Pithase!!!

> $ ls -l --full-time payload-cipher.bin
-rw-rw-r-- 1 gmg gmg 304 2025-06-09 01:28:31.245077416 +0000 payload-cipher.bin

> $ md5sum payload-cipher.bin
bf981b81f9caaff7e0c11f9646173eda  payload-cipher.bin

> $ hexdump -v -e '/1 "%02x"' payload-cipher.bin | tr -d '\n' ; echo
6269fc02061b9ef52ae01c4a85fb91bd4badb58bf25217382be02a4a85f7969d4348dd084ea3bea50b1d9463757ecebdda398e6d7f7efd810d39b433c65361352ae03b4a8ffd24e16269fc0d03531d314221f3c5f6689c1e6b66cd4ac7f9bebd6bb9b133d49f5e80612103c24eda56fd2b963e4b85e196808e2175c14e9872e52ae0f82647a09df562694410061b9eb9eb8eb48f323f24fd6269fc4f37c991f02aea040a721cd70aa91da3e9db531d317224cdfd47a09df56269b481ea0bd3cc9514c5498d5fa3f52a58244a8f1fba4d7069fc024a9279bdef5dd8b80e1b9ef52bea3b0a4b9264fa67217ffa0e6f95bc9da288254f9871fd89bc17c04e985ae5da55fc020653af0a6d6cb481c20b26c96269fc4a37e4d60aa566f94a85df8e4d5e69fc02b9199ef56266f992968b0e65
```

## Conclusión

Con cada ejecución, los primeros 8 bytes (la clave) cambian de forma aleatoria, por lo que el resto del payload aparece cifrado de manera distinta. 

Sin embargo, el loader lo descifra correctamente en memoria, de modo que su carga útil (“Proyecto Pithase!!!”) siempre se muestra sin alteraciones.

La comparación de fecha, tamaño y MD5 confirma que el archivo `payload-cipher.bin` se actualiza correctamente en cada corrida.
