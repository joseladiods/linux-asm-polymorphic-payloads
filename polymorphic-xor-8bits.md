# Polimorfismo XOR de 8 bits   

| Archivo | Descripción |
|---------|-------------|
| [`polymorphic-xor-8bits-payload-loader.asm`](./polymorphic-xor-8bits-payload-loader.asm) | Loader de payload contenido en un archivo cifrado con XOR, con reserva de memoria dinámica según el tamaño del payload y preparación de parámetros para payload polimórfico. |
| [`polymorphic-xor-8bits-payload.asm`](./polymorphic-xor-8bits-payload.asm) | Ejecuta su carga útil, en este caso un simple mensaje por STDOUT, y se **auto-cifra** con una clave de 8 bits [1-255] que se genera en el momento y sobreescribe el archivo que lo contenía. Con esta metodología logramos que el archivo que contiene el payload vaya variando constantemente. |

### Preparación
      
Compilar el payload ( polymorphic-xor-8bits-payload.asm )
```bash
> $ nasm -f bin polymorphic-xor-8bits-payload.asm -o polymorphic-xor-8bits-payload.bin
```
Agregarle al inicio del payload un byte nulo, donde se almacenará la clave con el que se **auto-cifrará** el payload en cada ejecución. El archivo **payload-cipher.bin** es el que será referenciado por el **loader**.

```bash
> $ ( printf '\x00'; cat polymorphic-xor-8bits-payload.bin ) > payload-cipher.bin
```
Compilar y enlazar el loader ( polymorphic-xor-8bits-payload-loader.asm )
```bash
> $ nasm -f elf64 polymorphic-xor-8bits-payload-loader.asm -o polymorphic-xor-8bits-payload-loader.o

> $ ld polymorphic-xor-8bits-payload-loader.o -o polymorphic-xor-8bits-payload-loader
```
Hacemos un paréntesis y ejecutamos algunos procedimientos que nos van a permitir observar los cambios que se van produciendo en el **payload**.     

Las variables a considerar para el análisis son: salida de la ejecución, horario de modificación, tamaño, hash MD5 y volcado en formato hexadecimal.

#### Payload original
```bash
> $ ls -l --full-time polymorphic-xor-8bits-payload.bin
-rw-rw-r-- 1 gmg gmg 253 2025-06-05 19:58:13.606715605 +0000 polymorphic-xor-8bits-payload.bin
```
```bash
> $ md5sum  polymorphic-xor-8bits-payload.bin
95c1864353e006fc3e2a6ebd623db9bd  polymorphic-xor-8bits-payload.bin
```
```bash
> $ hexdump -v -e '/1 "%02x"' polymorphic-xor-8bits-payload.bin | tr -d '\n' ; echo
4889e04883e00f4829c44989f44989cd4989d64883ec08682121210a48b820506974686173655048b850726f796563746f504831c048ffc04889c74889e6ba140000000f054883c4200f3184c07502fec088c34883ec1088042441bb03000000b8120000004c89e7488d3424ba010000004d31d20f054883f801740749ffcb745bebdd4883c4104d31ff41bb030000004883ec104d39f77d35438a443d0030d8880424b8120000004c89e7488d3424ba0100000049ffc74d89fa0f054883f801740a49ffcb742649ffcfebd7ebc64883c410b83c0000004831ff0f054883c410b83c0000004831ff48ffc70f054883c410b83c000000bf020000000f05
```
#### Payload con el byte inicial agregado
```bash
> $ ls -l --full-time payload-cipher.bin
-rw-rw-r-- 1 gmg gmg 254 2025-06-05 19:58:32.835861664 +0000 payload-cipher.bin
```
```bash
> $ md5sum payload-cipher.bin
01c8e58cb8e55f26ddc03ff9ff3e68dd  payload-cipher.bin
```
```bash
> $ hexdump -v -e '/1 "%02x"' payload-cipher.bin | tr -d '\n' ; echo   
004889e04883e00f4829c44989f44989cd4989d64883ec08682121210a48b820506974686173655048b850726f796563746f504831c048ffc04889c74889e6ba140000000f054883c4200f3184c07502fec088c34883ec1088042441bb03000000b8120000004c89e7488d3424ba010000004d31d20f054883f801740749ffcb745bebdd4883c4104d31ff41bb030000004883ec104d39f77d35438a443d0030d8880424b8120000004c89e7488d3424ba0100000049ffc74d89fa0f054883f801740a49ffcb742649ffcfebd7ebc64883c410b83c0000004831ff0f054883c410b83c0000004831ff48ffc70f054883c410b83c000000bf020000000f05
```

Observando las salidas, lo primero que notamos es que se produjo el incremento esperado de 1 byte en el archivo (253 → 254 bytes).

Como el volcado hexadecimal muestra, la única diferencia está en el primer byte (00), y el MD5 distinto confirma que el archivo cambió.

Finalmente hacemos la primer ejecución del **loader** para que el **payload** se **auto-cifre** con una clave distinta a 0 (esto es debido a que **XOR 0** mantiene los mismos valores, no modifica nada).

#### Primera ejecución
```bash
> $ ./polymorphic-xor-8bits-payload-loader
Proyecto Pithase!!!

> $ ls -l --full-time payload-cipher.bin
-rw-rw-r-- 1 gmg gmg 254 2025-06-05 21:22:56.753742208 +0000 payload-cipher.bin

> $ md5sum payload-cipher.bin
3bc477394b175dbe67994121a3184ebf  payload-cipher.bin

> $ hexdump -v -e '/1 "%02x"' payload-cipher.bin | tr -d '\n' ; echo
c78f4e278f4427c88fee038e4e338e4e0a8e4e118f442bcfafe6e6e6cd8f7fe797aeb3afa6b4a2978f7f97b5a8bea2a4b3a8978ff6078f38078f4e008f4e217dd3c7c7c7c8c28f4403e7c8f64307b2c539074f048f442bd74fc3e3867cc4c7c7c77fd5c7c7c78b4e208f4af3e37dc6c7c7c78af615c8c28f443fc6b3c08e380cb39c2c1a8f4403d78af638867cc4c7c7c78f442bd78afe30baf2844d83fac7f71f4fc3e37fd5c7c7c78b4e208f4af3e37dc6c7c7c78e38008a4e3dc8c28f443fc6b3cd8e380cb3e18e38082c102c018f4403d77ffbc7c7c78ff638c8c28f4403d77ffbc7c7c78ff6388f3800c8c28f4403d77ffbc7c7c778c5c7c7c7c8c2
```

Aquí ya podemos observar que el primer byte —la clave— ya no es **(00)**, sino **(c7)** y el resto del programa es totalmente distinto, debido a que se encuentra cifrado con la nueva clave.

Con el transcurrir de las ejecuciones observamos que "la parte útil" del payload –el mensaje por pantalla– se ejecuta correctamente y a través de las variables de análisis confirmamos que las versiones del payload son siempre distintas.

#### Segunda ejecución
```bash
> $ ./polymorphic-xor-8bits-payload-loader
Proyecto Pithase!!!

> $ ls -l --full-time payload-cipher.bin
-rw-rw-r-- 1 gmg gmg 254 2025-06-05 21:26:12.163278128 +0000 payload-cipher.bin

> $ md5sum payload-cipher.bin
2e1f9abab0a3f4e52063eea2b3d2d611  payload-cipher.bin

> $ hexdump -v -e '/1 "%02x"' payload-cipher.bin | tr -d '\n' ; echo
9dd5147dd51e7d92d5b459d41469d41450d4144bd51e7195f5bcbcbc97d525bdcdf4e9f5fceef8cdd525cdeff2e4f8fee9f2cdd5ac5dd5625dd5145ad5147b27899d9d9d9298d51e59bd92ac195de89f635d155ed51e718d1599b9dc269e9d9d9d258f9d9d9dd1147ad510a9b9279c9d9d9dd0ac4f9298d51e659ce99ad46256e9c67640d51e598dd0ac62dc269e9d9d9dd51e718dd0a46ae0a8de17d9a09dad451599b9258f9d9d9dd1147ad510a9b9279c9d9d9dd4625ad014679298d51e659ce997d46256e9bbd46252764a765bd51e598d25a19d9d9dd5ac629298d51e598d25a19d9d9dd5ac62d5625a9298d51e598d25a19d9d9d229f9d9d9d9298
```

#### Tercera ejecución
```bash
> $ ./polymorphic-xor-8bits-payload-loader
Proyecto Pithase!!!

> $ ls -l --full-time payload-cipher.bin
-rw-rw-r-- 1 gmg gmg 254 2025-06-05 21:26:33.923448316 +0000 payload-cipher.bin

> $ md5sum payload-cipher.bin
b3aae6ee5956bba6d6b850a4ad1c57ce  payload-cipher.bin

> $ hexdump -v -e '/1 "%02x"' payload-cipher.bin | tr -d '\n' ; echo
8bc3026bc3086b84c3a24fc2027fc20246c2025dc3086783e3aaaaaa81c333abdbe2ffe3eaf8eedbc333dbf9e4f2eee8ffe4dbc3ba4bc3744bc3024cc3026d319f8b8b8b848ec3084fab84ba0f4bfe89754b0348c308679b038fafca30888b8b8b33998b8b8bc7026cc306bfaf318a8b8b8bc6ba59848ec308738aff8cc27440ffd06056c3084f9bc6ba74ca30888b8b8bc308679bc6b27cf6bec801cfb68bbb53038faf33998b8b8bc7026cc306bfaf318a8b8b8bc2744cc60271848ec308738aff81c27440ffadc27444605c604dc3084f9b33b78b8b8bc3ba74848ec3084f9b33b78b8b8bc3ba74c3744c848ec3084f9b33b78b8b8b34898b8b8b848e
```

#### Cuarta ejecución
```bash
> $ ./polymorphic-xor-8bits-payload-loader
Proyecto Pithase!!!

> $ ls -l --full-time payload-cipher.bin
-rw-rw-r-- 1 gmg gmg 254 2025-06-05 21:26:52.099590352 +0000 payload-cipher.bin

> $ md5sum payload-cipher.bin
5501b6bd665005f7a186a976ebd8554b  payload-cipher.bin

> $ hexdump -v -e '/1 "%02x"' payload-cipher.bin | tr -d '\n' ; echo
9bd3127bd3187b94d3b25fd2126fd21256d2124dd3187793f3bababa91d323bbcbf2eff3fae8fecbd323cbe9f4e2fef8eff4cbd3aa5bd3645bd3125cd3127d218f9b9b9b949ed3185fbb94aa1f5bee99655b1358d318778b139fbfda20989b9b9b23899b9b9bd7127cd316afbf219a9b9b9bd6aa49949ed318639aef9cd26450efc07046d3185f8bd6aa64da20989b9b9bd318778bd6a26ce6aed811dfa69bab43139fbf23899b9b9bd7127cd316afbf219a9b9b9bd2645cd61261949ed318639aef91d26450efbdd26454704c705dd3185f8b23a79b9b9bd3aa64949ed3185f8b23a79b9b9bd3aa64d3645c949ed3185f8b23a79b9b9b24999b9b9b949e
```

## Conclusión

Con cada ejecución, el primer byte (la clave) cambia de forma aleatoria, por lo que el resto del payload aparece cifrado de manera distinta. 

Sin embargo, el loader lo descifra correctamente en memoria, de modo que su carga útil (“Proyecto Pithase!!!”) siempre se muestra sin alteraciones.

La comparación de fecha, tamaño y MD5 confirma que el archivo `payload-cipher.bin` se actualiza correctamente en cada corrida.
