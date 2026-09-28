;=============================================================================
; PRÁCTICA 1: SISTEMA DE SUPERVISIÓN DE TEMPERATURA
; Dispositivo: PIC18F4550
; Ensamblador: MPLAB XC8 (pic-as)
; Frecuencia de reloj: 8 MHz (Oscilador Interno)
;=============================================================================
#include <xc.inc>

; --- BITS DE CONFIGURACIÓN ---
CONFIG FOSC = INTOSCIO_EC   ; Oscilador interno, pin RA6 como E/S digital
CONFIG WDT = OFF            ; Watchdog Timer deshabilitado
CONFIG MCLRE = ON           ; Pin MCLR habilitado
CONFIG LVP = OFF            ; Programación en bajo voltaje deshabilitada
CONFIG PBADEN = OFF         ; RB0:RB4 inician como pines digitales

; --- DEFINICIÓN DE VARIABLES EN MEMORIA RAM (ACCESS BANK) ---
PSECT udata_acs
Flags:          DS 1        ; Bit 0: Flag de muestreo de Timer0
Modo_Escala:    DS 1        ; 0 = Celsius (°C), 1 = Fahrenheit (°F)
Temp_ADC_H:     DS 1        ; Byte alto de lectura ADC
Temp_ADC_L:     DS 1        ; Byte bajo de lectura ADC
Temp_C:         DS 1        ; Temperatura calculada en °C
Temp_F:         DS 1        ; Temperatura calculada en °F
Temp_Disp:      DS 1        ; Valor numérico a desplegar (0 a 99)
Dig_Dec:        DS 1        ; BCD decena
Dig_Uni:        DS 1        ; BCD unidad
Seg_Dec:        DS 1        ; Patrón 7 segmentos decena
Seg_Uni:        DS 1        ; Patrón 7 segmentos unidad
Temp_Val:       DS 1        ; Variable auxiliar de resta BCD
DivH:           DS 1        ; Variable auxiliar para cálculo °F
DivL:           DS 1        ; Variable auxiliar para cálculo °F
Cociente:       DS 1        ; Variable auxiliar división °F
Retardo1:       DS 1        ; Retardo de multiplexado
Retardo2:       DS 1        ; Retardo de multiplexado
Estado_Termico: DS 1        ; Bit 0: 0 = Menor/igual a 30°C, 1 = Mayor a 30°C

; --- VECTOR DE RESET (0x0000) ---
PSECT resetVec, class=CODE, reloc=2
ORG 0x0000
resetVec:
    GOTO Inicio

; --- VECTOR DE INTERRUPCIÓN DE ALTA PRIORIDAD (0x0008) ---
PSECT isrVec, class=CODE, reloc=2
ORG 0x0008
isrVec:
    GOTO ISR_General

; --- TABLA DE CARACTERES: DISPLAY 7 SEGMENTOS (CÁTODO COMÚN) ---
PSECT const_data, class=CONST, reloc=2
Tabla_7Seg:
    DB 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F

; --- CÓDIGO PRINCIPAL ---
PSECT main_code, class=CODE, reloc=2
Inicio:
    ; 1. Configurar oscilador a 8 MHz
    MOVLW 0x72              ; IRCF = 111 (8 MHz), SCS = 10 (reloj interno)
    MOVWF OSCCON, c

    ; 2. Configuración de puertos de E/S
    BSF TRISA, 0, c         ; RA0 entrada analógica (LM35)
    BSF TRISB, 0, c         ; RB0 (INT0)
    BSF TRISB, 1, c         ; RB1 (INT1)
    BSF TRISB, 2, c         ; RB2 (INT2)
    CLRF TRISC, c           ; PORTC salidas: RC0 (LED Alarma), RC1 (Ventilador), RC2 (D1), RC6 (D2)
    CLRF LATC, c
    CLRF TRISD, c           ; PORTD salidas: Segmentos a-g
    CLRF LATD, c
    CLRF Estado_Termico, c  ; Asumir inicialmente temperatura segura

    ; 3. Configuración de Resistencias Pull-Up en PORTB
    BCF INTCON2, 7, c       ; nRBPU = 0 (Pull-ups internos habilitados)

    ; 4. Configuración del Módulo ADC
    MOVLW 0x0E
    MOVWF ADCON1, c         ; AN0 analógico, resto digitales. Vref+ = VDD, Vref- = VSS
    MOVLW 0xA5
    MOVWF ADCON2, c         ; Justificación derecha, 8 TAD de adquisición, Fosc/16
    MOVLW 0x01
    MOVWF ADCON0, c         ; Canal AN0 seleccionado, módulo ADC encendido

    ; Configuración del Timer0 (Temporizador de muestreo ~500 ms)
    ; T0CON: 16 bits, reloj interno Fosc/4, prescaler 1:256, Timer0 encendido
    MOVLW 0x87
    MOVWF T0CON, c          ; 16 bits, reloj Fosc/4, prescaler 1:256, encendido
    MOVLW 0xF0
    MOVWF TMR0H, c
    MOVLW 0xBE
    MOVWF TMR0L, c

    ; 6. Configuración de Interrupciones
    BCF RCON, 7, c          ; IPEN = 0 (Sin prioridades)
    BCF INTCON2, 6, c       ; INTEDG0 = 0 (Flanco de bajada RB0)
    BCF INTCON2, 5, c       ; INTEDG1 = 0 (Flanco de bajada RB1)
    BCF INTCON2, 4, c       ; INTEDG2 = 0 (Flanco de bajada RB2)

    BCF INTCON, 1, c        ; Limpiar banderas
    BCF INTCON3, 0, c
    BCF INTCON3, 1, c
    BCF INTCON, 2, c

    ; Habilitación de interrupciones individuales
    BSF INTCON, 4, c        ; INT0IE = 1
    BSF INTCON3, 3, c       ; INT1IE = 1
    BSF INTCON3, 4, c       ; INT2IE = 1
    BSF INTCON, 5, c        ; TMR0IE = 1

    ; Habilitación global de interrupciones
    BSF INTCON, 6, c        ; PEIE = 1
    BSF INTCON, 7, c        ; GIE = 1

    ; 7. Inicialización de variables
    CLRF Flags, c
    CLRF Modo_Escala, c     ; Modo por defecto: °C
    CLRF Temp_C, c
    CLRF Temp_F, c
    CLRF Seg_Dec, c
    CLRF Seg_Uni, c

; --- BUCLE PRINCIPAL (MULTIPLEXADO DE DISPLAYS) ---
    
;=============================================================================
; ADQUISICIÓN Y CONVERSIÓN DE TEMPERATURA
;=============================================================================

    CALL Adquirir_Temperatura
    CALL Actualizar_Valor_Despliegue

Bucle_Principal:
    BTFSS Flags, 0, c
    GOTO Refrescar_Display

    BCF Flags, 0, c
    CALL Adquirir_Temperatura
    CALL Actualizar_Valor_Despliegue

Refrescar_Display:
    ; Mostrar Display 1 (Decenas)
    MOVF Seg_Dec, W, c
    MOVWF LATD, c
    BSF LATC, 2, c          ; Encender Display Decenas
    BCF LATC, 6, c          ; Apagar Display Unidades
    CALL Retardo_3ms

    ; Mostrar Display 2 (Unidades)
    MOVF Seg_Uni, W, c
    MOVWF LATD, c
    BCF LATC, 2, c          ; Apagar Display Decenas
    BSF LATC, 6, c          ; Encender Display Unidades
    CALL Retardo_3ms

    BCF LATC, 2, c          ; Apagar ambos displays (evita ghosting)
    BCF LATC, 6, c

    GOTO Bucle_Principal

;=============================================================================
; RUTINA DE INTERRUPCIÓN GENERAL (ISR)
;=============================================================================
ISR_General:
    ; --- Verificación de INT0 (Alarma manual - RB0) ---
    BTFSS INTCON, 1, c
    GOTO Test_INT1
    BCF INTCON, 1, c        ; Limpiar bandera INT0IF
    BTG LATC, 0, c          ; Alternar estado del LED de Alarma
    RETFIE 1

Test_INT1:
    ; --- Verificación de INT1 (Ventilador manual - RB1) ---
    BTFSS INTCON3, 0, c
    GOTO Test_INT2
    BCF INTCON3, 0, c       ; Limpiar bandera INT1IF
    BTG LATC, 1, c          ; Alternar estado del Ventilador
    RETFIE 1

Test_INT2:
    ; --- Verificación de INT2 (Cambio de Escala °C / °F - RB2) ---
    BTFSS INTCON3, 1, c
    GOTO Test_TMR0
    BCF INTCON3, 1, c       ; Limpiar bandera INT2IF
    BTG Modo_Escala, 0, c   ; Alternar escala
    CALL Actualizar_Valor_Despliegue
    RETFIE 1 

Test_TMR0:
    ; --- Verificación de Timer0 (Período de muestreo) ---
    BTFSS INTCON, 2, c
    GOTO Fin_ISR
    BCF INTCON, 2, c        ; Limpiar bandera TMR0IF
    MOVLW 0xF0
    MOVWF TMR0H, c
    MOVLW 0xBE
    MOVWF TMR0L, c
    BSF Flags, 0, c         ; Solicitar muestreo al bucle principal

Fin_ISR:
    RETFIE 1

;=============================================================================
; ADQUISICIÓN DE TEMPERATURA
;=============================================================================
Adquirir_Temperatura:
    BSF ADCON0, 1, c        ; GO/nDONE = 1
Espera_ADC:
    BTFSC ADCON0, 1, c
    GOTO Espera_ADC

    MOVF ADRESH, W, c
    MOVWF Temp_ADC_H, c
    MOVF ADRESL, W, c
    MOVWF Temp_ADC_L, c

    ; Temp_C = ADC >> 1
    BCF STATUS, 0, c
    RRCF Temp_ADC_H, F, c
    RRCF Temp_ADC_L, F, c
    MOVF Temp_ADC_L, W, c
    MOVWF Temp_C, c

    ; --- COMPROBACIÓN DE UMBRAL (CORRECCIÓN CLAVE) ---
    CALL Verificar_Umbral_30C

    ; Conversión a Fahrenheit: F = (C * 9)/5 + 32
    MOVF Temp_C, W, c
    MULLW 9
    MOVF PRODL, W, c
    MOVWF DivL, c
    MOVF PRODH, W, c
    MOVWF DivH, c
    CLRF Cociente, c

Division_Entre_5:
    MOVLW 5
    SUBWF DivL, F, c
    MOVLW 0
    SUBWFB DivH, F, c
    BNC Fin_Division
    INCF Cociente, F, c
    GOTO Division_Entre_5

Fin_Division:
    MOVLW 32
    ADDWF Cociente, W, c
    MOVWF Temp_F, c
    RETURN


; PREPARACIÓN DEL VALOR PARA DESPLIEGUE

Actualizar_Valor_Despliegue:
    BTFSS Modo_Escala, 0, c
    GOTO Cargar_Celsius

    MOVF Temp_F, W, c
    MOVWF Temp_Disp, c
    GOTO Descomponer_BCD

Cargar_Celsius:
    MOVF Temp_C, W, c
    MOVWF Temp_Disp, c

Descomponer_BCD:
    MOVF Temp_Disp, W, c
    MOVWF Temp_Val, c
    CLRF Dig_Dec, c

Bucle_Decenas:
    MOVLW 10
    SUBWF Temp_Val, W, c
    BNC Fin_Decenas
    MOVWF Temp_Val, c
    INCF Dig_Dec, F, c
    GOTO Bucle_Decenas

Fin_Decenas:
    MOVF Temp_Val, W, c
    MOVWF Dig_Uni, c

    ; Buscar patrón de Decena
    CLRF TBLPTRU, c
    MOVLW low(Tabla_7Seg)
    MOVWF TBLPTRL, c
    MOVLW high(Tabla_7Seg)
    MOVWF TBLPTRH, c
    MOVF Dig_Dec, W, c
    ADDWF TBLPTRL, F, c
    MOVLW 0
    ADDWFC TBLPTRH, F, c
    TBLRD*
    MOVF TABLAT, W, c
    MOVWF Seg_Dec, c

    ; Buscar patrón de Unidad
    CLRF TBLPTRU, c
    MOVLW low(Tabla_7Seg)
    MOVWF TBLPTRL, c
    MOVLW high(Tabla_7Seg)
    MOVWF TBLPTRH, c
    MOVF Dig_Uni, W, c
    ADDWF TBLPTRL, F, c
    MOVLW 0
    ADDWFC TBLPTRH, F, c
    TBLRD*
    MOVF TABLAT, W, c
    MOVWF Seg_Uni, c
    RETURN


; CONTROL POR TRANSICIÓN TÉRMICA (PRIORIDAD AL USUARIO)

Verificar_Umbral_30C:
    MOVLW 30
    CPFSGT Temp_C, c        ; ¿Temp_C > 30?
    BRA Evaluar_Zona_Fria

    ; Caso: Temperatura ACTUAL > 30 °C
    BTFSC Estado_Termico, 0, c
    RETURN                  ; Si ya estaba en > 30°C, respeta el pulsador

    ; Transición de frío a caliente (Disparo de alarma):
    BSF Estado_Termico, 0, c 
    BSF LATC, 0, c          ; Encender LED Alarma (RC0)
    BSF LATC, 1, c          ; Encender Ventilador (RC1)
    RETURN

Evaluar_Zona_Fria:
    ; Caso: Temperatura ACTUAL <= 30 °C
    BTFSS Estado_Termico, 0, c
    RETURN                  ; Si ya estaba fría, respeta el pulsador

    ; Transición de caliente a frío (Normalización):
    BCF Estado_Termico, 0, c 
    BCF LATC, 0, c          ; Apagar LED Alarma (RC0)
    BCF LATC, 1, c          ; Apagar Ventilador (RC1)
    RETURN


;  (~3 ms a 8 MHz)

Retardo_3ms:
    MOVLW 10
    MOVWF Retardo1, c
Loop_Ext:
    MOVLW 200
    MOVWF Retardo2, c
Loop_Int:
    DECFSZ Retardo2, F, c
    GOTO Loop_Int
    DECFSZ Retardo1, F, c
    GOTO Loop_Ext
    RETURN

END resetVec