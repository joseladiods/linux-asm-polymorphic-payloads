;================================================================================================================================
; Archivo      : polymorphic-xor-64bits-nop-payload.asm
; Creado       : 08/06/2025
; Modificado   : 08/06/2025
; Autor        : Gastón M. González
; Plataforma   : Linux
; Arquitectura : x86-64
; Descripción  : Ejecuta su carga útil, en este caso un simple mensaje por STDOUT, y se auto-cifra, recorriendo el código
;                en bloques de 8 bytes, aplicando a cada bloque una operación XOR con una clave de 64 bits [1, 2^64 - 1]
;                generada en tiempo de ejecución, y sobreescribe el archivo que lo contenía.
;                Con esta metodología logramos que el archivo que contiene el payload vaya variando constantemente.
;
;                Para que el payload se pueda autocifrar y sobrescribirse recibe registros con la siguiente
;                información:
;
;                RSI <- (fd) descriptor archivo
;                RCX <- dirección base en memoria del payload (de este programa)
;                RDX <- tamaño del payload
;
;                Tras compilar, calculamos cuántos bytes hacen falta para que la longitud del payload (archivo completo
;                menos 1 byte de clave) sea múltiplo de 8, y rellenamos esos bytes extras con instrucciones NOP. De este
;                modo, al cifrar en bloques de 8 bytes no quedan restos y evitamos añadir lógica adicional para procesar
;                y rellenar los sobrantes.
;
;                Una vez compilado, el payload ocupó 291 bytes. Como 291 no es múltiplo de 8 (291 mod 8 = 3), calculamos:
;                bytes_adicionales = 8 - (291 mod 8) => 8 - 3 = 5.
;
;                Al final del código se encuentran los 5 NOP (cada NOP ocupa 1 byte y no tienen ningún efecto).
;
; Compilar     : nasm -f bin polymorphic-xor-64bits-nop-payload.asm -o polymorphic-xor-64bits-nop-payload.bin
; Preparar     : ( printf '\x00\x00\x00\x00\x00\x00\x00\x00'; cat polymorphic-xor-64bits-nop-payload.bin ) > payload-cipher.bin
;================================================================================================================================
; Licencia MIT:
; Este código es de uso libre bajo los términos de la Licencia MIT.
; Puedes usarlo, modificarlo y redistribuirlo, siempre que incluyas esta nota de atribución.
; NO HAY GARANTÍA DE NINGÚN TIPO, EXPRESA O IMPLÍCITA.
; Licencia completa en: https://github.com/Pithase/asm-payloads-loaders/blob/main/LICENSE
;================================================================================================================================

BITS 64
global _start

%define MSG_LEN 20                 ; longitud del mensaje, que debe coincidir con las cadenas que se "pushean"

section .text
_start:
    ;============================================================================================================================
    ; 1. Alinear RSP a 16 bytes para cumplir con el estándar ABI (RSP mod 16 = 0)
    ;============================================================================================================================
    mov   rax, rsp                 ; RAX = valor actual de RSP
    and   rax, 0xF                 ; RAX = RSP mod 16 (es el resto de RSP/16)
    sub   rsp, rax                 ; RSP = RSP - (RSP mod 16) -> ahora RSP ≡ 0 mod 16 (RSP es congruente con 0 módulo 16)

    ;============================================================================================================================
    ; 2. Guarda los parámetros que disponibilizó el loader
    ;============================================================================================================================
    mov   r12, rsi                 ; R12 <- (fd) descriptor archivo
    mov   r13, rcx                 ; R13 <- dirección base en memoria (de este programa)
    mov   r14, rdx                 ; R14 <- tamaño del payload

    ;============================================================================================================================
    ; 3. Lo que "ejecuta" el payload, un mensaje por STDOUT
    ;============================================================================================================================
    sub   rsp, 8                   ; relleno (padding) de 8 bytes para dejar alineada la pila luego de los 3 push

    push  0x0A212121               ; "!!!\n"     (4 bytes de mensaje y 8 bytes en pila)
    mov   rax, 0x6573616874695020  ; " Pithase"  (8 bytes de mensaje y 8 bytes en pila)
    push  rax
    mov   rax, 0x6F746365796F7250  ; "Proyecto"  (8 bytes de mensaje y 8 bytes en pila)
    push  rax

    xor   rax, rax
    inc   rax                      ; syscall: write
    mov   rdi, rax                 ; fd = STDOUT
    mov   rsi, rsp                 ; dirección actual de RSP (comienzo de "Proyecto Pithase!!!\n")
    mov   rdx, MSG_LEN             ; longitud total de bytes a escribir
    syscall                        ; write(1, buffer, MSG_LEN)

    add   rsp, 32                  ; reposiciona RSP (libera 32 bytes = 8 padding + 24 de push)

    ;============================================================================================================================
    ; 4. Genera clave de 64 bits (sin ningún byte igual a cero)
    ;============================================================================================================================
    rdrand rax                     ; intenta leer 64 bits de aleatoriedad hardware
    jnc   .use_tsc                 ; CF = 0 -> RDRAND no disponible -> utilizamos a TSC
    jmp   .got_key                 ; se obtuvo la clave

.use_tsc:
    rdtsc                          ; RDX:RAX = timestamp counter
    shl   rdx, 32                  ; mueve los 32 bits bajos de RDX a su parte alta
    or    rax, rdx                 ; combina los registros

.got_key:
    xor   r10, r10                 ; índice del byte = 0

.fix_loop:
    test  al, al                   ; examina solo el byte más bajo de RAX (AL)
    jnz   .next_byte               ; si AL != 0, salta (no necesita corrección)
    inc   rax                      ; si AL = 0, incrementa RAX (suma 1 al byte bajo)

.next_byte:
    ror   rax, 8                   ; rota RAX 8 bits a la derecha
    inc   r10                      ; incrementa índice
    cmp   r10, 8                   ; ¿todos los bytes examinados?
    jne   .fix_loop                ; si no, continúa

.key_ready:
    mov   rbx, rax                 ; RBX <- clave final

    ;============================================================================================================================
    ; 5. Escribe la clave en el offset 0 del archivo
    ;============================================================================================================================
    sub   rsp, 16                  ; reserva 16 bytes en la pila
    mov   [rsp], rax               ; guarda la clave en la pila

    mov   r11, 3                   ; R11 = contador de intentos de escritura restantes

.key_write_retry:
    mov   rax, 18                  ; syscall: pwrite64
    mov   rdi, r12                 ; (fd) descriptor de archivo heredado
    lea   rsi, [rsp]               ; puntero al byte que se va a escribir
    mov   rdx, 8                   ; longitud total de bytes a escribir
    xor   r10, r10                 ; offset = 0
    syscall                        ; pwrite64(fd, buffer, 8, 0)

    cmp   rax, 8                   ; ¿ grabó 8 byte ?
    je    .key_write_success       ; si sí, continúa normalmente

    dec   r11                      ; disminuye contador de intentos
    jz    .key_write_failure       ; si R11 = 0, se terminaron los intentos de escritura
    jmp   .key_write_retry         ; si aún quedan intentos, repetir la escritura

.key_write_success:
    add   rsp, 16                  ; reposiciona RSP

    ;============================================================================================================================
    ; 6. Recorre la memoria byte a byte, los cifra y graba el archivo
    ;============================================================================================================================
    xor   r15, r15                 ; índice = 0
    mov   r11, 3                   ; R11 = contador de intentos globales de escritura restantes
    sub   rsp, 16                  ; reserva 16 bytes en la pila

.cipher_loop:
    cmp   r15, r14                 ; ¿ ya me recorrí todo :-) ?
    jge  .cipher_done              ; si índice >= payload_size, finalizo

    mov   rax, [r13 + r15]         ; lee 8 bytes (comienza de la base y va incrementando)
    xor   rax, rbx                 ; aplica XOR con la clave generada
    mov   [rsp], rax               ; almacena el bloque d8 bytes cifrado

.cipher_write_retry:
    mov   rax, 18                  ; syscall: pwrite64
    mov   rdi, r12                 ; (fd) descriptor de archivo heredado
    lea   rsi, [rsp]               ; buffer = al byte cifrado
    mov   rdx, 8                   ; longitud total de bytes a escribir
    add   r15, 8                   ; incrementa el índice en 8 bytes
    mov   r10, r15                 ; offset = índice (el archivo está desplazado 8 byte respecto al payload en memoria)
    syscall

    cmp  rax, 8                    ; ¿ grabó 8 bytes ?
    je   .cipher_write_success     ; si sí, continúa normalmente

    dec   r11                      ; disminuye contador de intentos
    jz    .cipher_write_failure    ; si R11 = 0, se terminaron los intentos de escritura
    sub   r15, 8                   ; vuelvo al mismo valor que tenía antes del error
    jmp   .cipher_write_retry      ; si aún quedan intentos, repetir la escritura

.cipher_write_success:
    jmp   .cipher_loop             ; reinicia el proceso

.cipher_done:
    add   rsp, 16                  ; reposiciona RSP

    ;============================================================================================================================
    ; 7. Salida
    ;============================================================================================================================
    mov   rax, 60                  ; syscall: exit
    xor   rdi, rdi
    syscall                        ; exit(0)

.key_write_failure:
    add   rsp, 16                  ; reposiciona RSP

    mov   rax, 60                  ; syscall: exit
    xor   rdi, rdi
    inc   rdi
    syscall                        ; exit(1)

.cipher_write_failure:
    add   rsp, 16                  ; reposiciona RSP

    mov   rax, 60                  ; syscall: exit
    mov   rdi, 2
    syscall                        ; exit(2)

    ;============================================================================================================================
    ; 8. Relleno para lograr que el tamaño del payload se múltiplo de 8
    ;============================================================================================================================
    nop                            ; no hace nada, el tamaño de la instrucción es de 1 byte
    nop
    nop
    nop
    nop
