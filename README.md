# TurismoUQ · Plataforma de reservas turísticas del Quindío

Proyecto integrador de Bases de Datos II, periodo 2026-2.
Universidad del Quindío · Ingeniería de Sistemas y Computación.
Docente: Carolina Londoño Idárraga.

## Integrantes
- Juan David Martinez
- Santiago Ramirez
- Sebastian Amaya

## Requisitos
- Oracle Database XE 21c (servicio XEPDB1, puerto 1521) u Oracle Database Free (servicio FREEPDB1)
- Oracle SQL Developer
- Los scripts usan solo funciones disponibles desde Oracle 12c, así que sirven en ambas versiones.

## Orden de ejecución sobre una base limpia

Cada script se ejecuta completo de arriba hacia abajo (F5 / Run Script en SQL Developer).

### Entrega 1 · Modelo y consultas de análisis
| Orden | Script | Conexión | Qué hace |
|---|---|---|---|
| 1 | scripts/00_crear_usuario.sql | SYSTEM en la PDB | Crea el esquema TURISMOUQ y sus privilegios |
| 2 | scripts/01_ddl.sql | TURISMOUQ | Elimina y crea tablas, restricciones y comentarios |
| 3 | scripts/02_carga.sql | TURISMOUQ | Carga datos con PL/SQL y DBMS_RANDOM |
| 4 | scripts/03_consultas.sql | TURISMOUQ | Siete consultas de análisis, numeradas y comentadas |

### Entrega 2 · Capa PL/SQL
| Orden | Script | Conexión | Qué hace |
|---|---|---|---|
| 5 | scripts/04_paquete_reservas.sql | TURISMOUQ | Paquete PKG_RESERVAS: `fn_valor_estadia`, `sp_crear_reserva` y `sp_liquidacion_mensual` (cursor explícito con parámetros); tabla LIQUIDACION_MENSUAL |
| 6 | scripts/05_disparadores.sql | TURISMOUQ | Disparador de sentencia de auditoría de TARIFA y disparador de fila contra solapes de reservas; tabla TARIFA_AUDITORIA |
| 7 | scripts/06_tablespace_historico.sql | SYSTEM en la PDB | Crea el tablespace TS_HISTORICO_RESERVAS (con su justificación) y da cuota al esquema |
| 8 | scripts/07_historico_y_vista_materializada.sql | TURISMOUQ | Tabla RESERVA_HISTORICO en el tablespace propio y vista materializada MV_OCUPACION_MENSUAL (con su política de refresco) |
| 9 | scripts/08_pruebas.sql | TURISMOUQ | Evidencia de prueba de cada componente |

Las pruebas del script 08 no dejan datos de prueba: lo que escriben se deshace con ROLLBACK, salvo la liquidación mensual.

## Documentación
- docs/ contiene el documento con el MER, las reglas de negocio y las decisiones de diseño.
