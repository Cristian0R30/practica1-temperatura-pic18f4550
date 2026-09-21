
#include <xc.inc>

CONFIG FOSC = INTOSCIO_EC
CONFIG WDT = OFF
CONFIG MCLRE = ON
CONFIG LVP = OFF
CONFIG PBADEN = OFF

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

PSECT resetVec, class=CODE, reloc=2
ORG 0x0000

resetVec:
    GOTO Inicio

PSECT main_code, class=CODE, reloc=2

Inicio:
    MOVLW 0x72
    MOVWF OSCCON, c

Bucle_Principal:
    GOTO Bucle_Principal

END resetVec

