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

### Entrega 3 · Transacciones, índices y seguridad
| Orden | Script | Conexión | Qué hace |
|---|---|---|---|
| 10 | scripts/09_transacciones.sql | TURISMOUQ | Paquete PKG_TRANSACCIONES: `sp_reserva_con_pago` (reserva + pago atómicos, SAVEPOINT y rollback parcial del servicio opcional) y `sp_reservar_con_bloqueo` (SELECT ... FOR UPDATE); demostración paso a paso de un rollback parcial |
| — | scripts/10_concurrencia.sql | TURISMOUQ, dos sesiones | Experimento de dos sesiones reservando la misma habitación, sin y con FOR UPDATE. Se ejecuta a mano en dos hojas de trabajo no compartidas, alternando los pasos T1…T9 |
| 11 | scripts/11_indices.sql | TURISMOUQ | Tres consultas con plan y tiempo antes y después: índice compuesto, basado en función y B-tree sobre FK; caso donde el índice no ayuda |
| 12 | scripts/12_vistas_recepcion.sql | TURISMOUQ | Vistas V_REC_* por las que trabaja recepción |
| 13 | scripts/13_seguridad.sql | SYSTEM en la PDB | Perfil con límites de sesión, cuatro roles (recepción, administrador de alojamiento, gerente, auditor), usuarios de prueba y GRANT |
| 14 | scripts/14_pruebas.sql | Cambia de usuario con CONNECT | Cada rol intenta lo que puede y lo que no; bloqueo por intentos fallidos (los errores ORA-00942, ORA-01031, ORA-01017 y ORA-28000 son esperados) |

Usuarios de prueba (perfil PERFIL_TURISMOUQ): `uq_recepcion`, `uq_admin_aloj`, `uq_gerente`, `uq_auditor`; las claves están en 13_seguridad.sql.

## Prueba en base limpia
Los scripts 00 a 14 se ejecutaron de arriba abajo, en el orden de las tablas anteriores, sobre un usuario TURISMOUQ nuevo: 0 objetos inválidos al final. El script 00 borra y vuelve a crear el usuario, así que no debe haber sesiones de TURISMOUQ abiertas al ejecutarlo.

## Evidencias
- `evidencias/08_pruebas_salida.txt`: pruebas de la Entrega 2.
- `evidencias/09_transacciones_salida.txt`: rollback parcial y transacción atómica.
- `evidencias/10_concurrencia_salida.txt`: las dos sesiones en paralelo, sin y con FOR UPDATE.
- `evidencias/11_indices_salida.txt`: planes de ejecución y tiempos antes y después.
- `evidencias/12_vistas_recepcion_salida.txt`: vistas de recepción.
- `evidencias/14_pruebas_salida.txt`: pruebas de seguridad de la Entrega 3.

## Documentación
- docs/ contiene el documento con el MER, las reglas de negocio y las decisiones de diseño.
