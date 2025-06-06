;==========================================================================================================================
; Archivo      : polymorphic-xor-8bits-payload.asm
; Creado       : 05/06/2025
; Modificado   : 05/06/2025
; Autor        : Gastón M. González
; Plataforma   : Linux
; Arquitectura : x86-64
; Descripción  : Ejecuta su carga útil, en este caso un simple mensaje por STDOUT, y se auto-cifra con una clave
;                de 8 bits [1-255] que se genera en el momento y sobreescribe el archivo que lo contenía.
;                Con esta metodología logramos que el archivo que contiene el payload vaya variando constantemente.
;
;                Para que el payload se pueda autocifrar y sobrescribirse recibe registros con la siguiente
;                información:
;
;                RSI <- (fd) descriptor archivo
;                RCX <- dirección base en memoria del payload (de este programa)
;                RDX <- tamaño del payload
;
; Compilar     : nasm -f bin polymorphic-xor-8bits-payload.asm -o polymorphic-xor-8bits-payload.bin
; Preparar     : ( printf '\x00'; cat polymorphic-xor-8bits-payload.bin ) > payload-cipher.bin
;==========================================================================================================================
; Licencia MIT:
; Este código es de uso libre bajo los términos de la Licencia MIT.
; Puedes usarlo, modificarlo y redistribuirlo, siempre que incluyas esta nota de atribución.
; NO HAY GARANTÍA DE NINGÚN TIPO, EXPRESA O IMPLÍCITA.
; Licencia completa en: https://github.com/Pithase/asm-payloads-loaders/blob/main/LICENSE
;==========================================================================================================================

BITS 64
global _start

%define MSG_LEN 20                 ; longitud del mensaje, que debe coincidir con las cadenas que se "pushean"

section .text
_start:
    ;======================================================================================================================
    ; 1. Alinear RSP a 16 bytes para cumplir con el estándar ABI (RSP mod 16 = 0)
    ;======================================================================================================================
    mov   rax, rsp                 ; RAX = valor actual de RSP
    and   rax, 0xF                 ; RAX = RSP mod 16 (es el resto de RSP/16)
    sub   rsp, rax                 ; RSP = RSP - (RSP mod 16) -> ahora RSP ≡ 0 mod 16 (RSP es congruente con 0 módulo 16)

    ;======================================================================================================================
    ; 2. Guarda los parámetros que disponibilizó el loader
    ;======================================================================================================================
    mov   r12, rsi                 ; R12 <- (fd) descriptor archivo
    mov   r13, rcx                 ; R13 <- dirección base en memoria (de este programa)
    mov   r14, rdx                 ; R14 <- tamaño del payload

    ;======================================================================================================================
    ; 3. Lo que "ejecuta" el payload, un mensaje por STDOUT
    ;======================================================================================================================
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

    ;======================================================================================================================
    ; 4. Genera clave de 8 bits
    ;======================================================================================================================
    rdtsc                          ; RDX:RAX = timestamp counter
    test  al, al                   ; ¿ clave  != 0 ?
    jnz   .key_success             ; si sí, continúa normalmente
    inc   al                       ; aseguro que la clave es != 0 para forzar a que cambie el contenido del archivo

.key_success:
    mov   bl, al                   ; BL <- clave

    ;======================================================================================================================
    ; 5. Escribe la clave en el offset 0 del archivo
    ;======================================================================================================================
    sub   rsp, 16                  ; reserva 16 bytes en la pila
    mov   [rsp], al                ; guarda la clave en la pila

    mov   r11, 3                   ; R11 = contador de intentos de escritura restantes

.key_write_retry:
    mov   rax, 18                  ; syscall: pwrite64
    mov   rdi, r12                 ; (fd) descriptor de archivo heredado
    lea   rsi, [rsp]               ; puntero al byte que se va a escribir
    mov   rdx, 1                   ; longitud total de bytes a escribir
    xor   r10, r10                 ; offset = 0
    syscall                        ; pwrite64(fd, buffer, 1, 0)

    cmp   rax, 1                   ; ¿ grabó 1 byte ?
    je    .key_write_success       ; si sí, continúa normalmente

    dec   r11                      ; disminuye contador de intentos
    jz    .key_write_failure       ; si R11 = 0, se terminaron los intentos de escritura
    jmp   .key_write_retry         ; si aún quedan intentos, repetir la escritura

.key_write_success:
    add   rsp, 16                  ; reposiciona RSP

    ;======================================================================================================================
    ; 6. Recorre la memoria byte a byte, los cifra y graba el archivo
    ;======================================================================================================================
    xor   r15, r15                 ; índice = 0
    mov   r11, 3                   ; R11 = contador de intentos globales de escritura restantes
    sub   rsp, 16                  ; reserva 16 bytes en la pila

.cipher_loop:
    cmp   r15, r14                 ; ¿ ya me recorrí todo :-) ?
    jge  .cipher_done              ; si índice >= payload_size, finalizo

    mov   al, [r13 + r15]          ; leer byte (comienza de la base y va incrementando)
    xor   al, bl                   ; aplica XOR con la clave generada
    mov   [rsp], al                ; almacena el byte cifrado

.cipher_write_retry:
    mov   rax, 18                  ; syscall: pwrite64
    mov   rdi, r12                 ; (fd) descriptor de archivo heredado
    lea   rsi, [rsp]               ; buffer = al byte cifrado
    mov   rdx, 1                   ; longitud total de bytes a escribir
    inc   r15                      ; incrementa el índice
    mov   r10, r15                 ; offset = índice (el archivo está desplazado 1 byte respecto al payload en memoria)
    syscall

    cmp  rax, 1                    ; ¿ grabó 1 byte ?
    je   .cipher_write_success     ; si sí, continúa normalmente

    dec   r11                      ; disminuye contador de intentos
    jz    .cipher_write_failure    ; si R11 = 0, se terminaron los intentos de escritura
    dec   r15                      ; vuelvo al mismo valor que tenía antes del error
    jmp   .cipher_write_retry      ; si aún quedan intentos, repetir la escritura

.cipher_write_success:
    jmp   .cipher_loop             ; reinicia el proceso

.cipher_done:
    add   rsp, 16                  ; reposiciona RSP

    ;======================================================================================================================
    ; 7. Salida
    ;======================================================================================================================
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
