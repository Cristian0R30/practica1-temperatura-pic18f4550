
;=============================================================================
; PRÁCTICA 1: SISTEMA DE SUPERVISIÓN DE TEMPERATURA
; Dispositivo: PIC18F4550
; Ensamblador: MPLAB XC8 (pic-as)
; Frecuencia de reloj: 8 MHz (Oscilador Interno)
;=============================================================================
#include <xc.inc>

; --- BITS DE CONFIGURACIÓN ---
CONFIG FOSC = INTOSCIO_EC
CONFIG WDT = OFF
CONFIG MCLRE = ON
CONFIG LVP = OFF
CONFIG PBADEN = OFF

; --- DEFINICIÓN DE VARIABLES EN MEMORIA RAM (ACCESS BANK) ---
PSECT udata_acs
Flags:          DS 1
Modo_Escala:    DS 1
Temp_ADC_H:     DS 1
Temp_ADC_L:     DS 1
Temp_C:         DS 1
Temp_F:         DS 1
Temp_Disp:      DS 1
Dig_Dec:        DS 1
Dig_Uni:        DS 1
Seg_Dec:        DS 1
Seg_Uni:        DS 1
Temp_Val:       DS 1
DivH:           DS 1
DivL:           DS 1
Cociente:       DS 1
Retardo1:       DS 1
Retardo2:       DS 1


; --- VECTOR DE INTERRUPCIÓN DE ALTA PRIORIDAD (0x0008) ---
PSECT isrVec, class=CODE, reloc=2
ORG 0x0008

; --- CÓDIGO PRINCIPAL ---
PSECT main_code, class=CODE, reloc=2

; --- VECTOR DE RESET ---
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
; Patrones en orden 0-9: a, b, c, d, e, f, g
PSECT const_data, class=CONST, reloc=2

Tabla_7Seg:
    DB 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F

; --- CÓDIGO PRINCIPAL ---
PSECT main_code, class=CODE, reloc=2

Inicio:
    ; 1. Configurar oscilador a 8 MHz
    MOVLW 0x72
    MOVWF OSCCON, c

    ; 2. Configuración de puertos de E/S
    ; RA0 como entrada analógica (LM35)
    BSF TRISA, 0, c
    ; RB0, RB1, RB2 como entradas de interrupción
    BSF TRISB, 0, c
    BSF TRISB, 1, c
    BSF TRISB, 2, c
    ; PORTC como salidas: RC0 (LED Alarma), RC1 (Ventilador), RC2 (D1), RC3 (D2)
    CLRF TRISC, c
    CLRF LATC, c
    ; PORTD completo como salida (Segmentos a-g)
    CLRF TRISD, c
    CLRF LATD, c

    ; 3. Configuración de Resistencias Pull-Up en PORTB
    BCF INTCON2, 7, c

    ; 4. Configuración del Módulo ADC
    MOVLW 0x0E
    MOVWF ADCON1, c
    MOVLW 0xA5
    MOVWF ADCON2, c
    MOVLW 0x01
    MOVWF ADCON0, c

    ; 5. Configuración del Timer0 (Temporizador de muestreo ~500 ms)
    MOVLW 0x87
    MOVWF T0CON, c
    MOVLW 0xF0
    MOVWF TMR0H, c
    MOVLW 0xBE
    MOVWF TMR0L, c

    ; 6. Configuración de Interrupciones
    BCF RCON, 7, c

    ; Flancos de bajada para pulsadores
    BCF INTCON2, 6, c
    BCF INTCON2, 5, c
    BCF INTCON2, 4, c

    ; Limpieza de banderas de interrupción
    BCF INTCON, 1, c
    BCF INTCON3, 0, c
    BCF INTCON3, 1, c
    BCF INTCON, 2, c

    ; Habilitación de interrupciones individuales
    BSF INTCON, 4, c
    BSF INTCON3, 3, c
    BSF INTCON3, 4, c
    BSF INTCON, 5, c

    ; Habilitación global de interrupciones
    BSF INTCON, 6, c
    BSF INTCON, 7, c

    ; 7. Inicialización de variables
    CLRF Flags, c
    CLRF Modo_Escala, c
    CLRF Temp_C, c
    CLRF Temp_F, c
    CLRF Seg_Dec, c
    CLRF Seg_Uni, c


;=============================================================================
; ADQUISICIÓN Y CONVERSIÓN DE TEMPERATURA
;=============================================================================

    CALL Adquirir_Temperatura

Bucle_Principal:
    BTFSS Flags, 0, c
    GOTO Bucle_Principal

    BCF Flags, 0, c
    CALL Adquirir_Temperatura
    GOTO Bucle_Principal


;=============================================================================
; RUTINA DE INTERRUPCIÓN GENERAL
;=============================================================================

ISR_General:
    ; --- Verificación de INT0 (Alarma manual - RB0) ---
    BTFSS INTCON, 1, c
    GOTO Test_INT1
    BCF INTCON, 1, c
    BTG LATC, 0, c
    RETFIE 1

Test_INT1:
    ; --- Verificación de INT1 (Ventilador manual - RB1) ---
    BTFSS INTCON3, 0, c
    GOTO Test_INT2
    BCF INTCON3, 0, c
    BTG LATC, 1, c
    RETFIE 1

Test_INT2:
    ; --- Verificación de INT2 (Cambio de Escala °C / °F - RB2) ---
    BTFSS INTCON3, 1, c
    GOTO Test_TMR0
    BCF INTCON3, 1, c
    BTG Modo_Escala, 0, c
    RETFIE 1

Test_TMR0:
    ; --- Verificación de Timer0 (Período de muestreo) ---
    BTFSS INTCON, 2, c
    GOTO Fin_ISR
    BCF INTCON, 2, c

    MOVLW 0xF0
    MOVWF TMR0H, c
    MOVLW 0xBE
    MOVWF TMR0L, c

    BSF Flags, 0, c

Fin_ISR:
    RETFIE 1


;=============================================================================
; ADQUISICIÓN DE TEMPERATURA
;=============================================================================

Adquirir_Temperatura:

    BSF ADCON0, 1, c

Espera_ADC:
    BTFSC ADCON0, 1, c
    GOTO Espera_ADC

    MOVF ADRESH, W, c
    MOVWF Temp_ADC_H, c

    MOVF ADRESL, W, c
    MOVWF Temp_ADC_L, c

    BCF STATUS, 0, c
    RRCF Temp_ADC_H, F, c
    RRCF Temp_ADC_L, F, c

    MOVF Temp_ADC_L, W, c
    MOVWF Temp_C, c

    MOVF Temp_C, W, c
    MULLW 9

    MOVF PRODL, W, c
    MOVWF DivL, c

    MOVF PRODH, W, c
    MOVWF DivH, c

    CLRF Cociente, c


;=============================================================================
; CONVERSIÓN A FAHRENHEIT
;=============================================================================

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

END resetVec

