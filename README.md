# TurismoUQ · Plataforma de reservas turísticas del Quindío

Proyecto integrador de Bases de Datos II, periodo 2026-2.
Universidad del Quindío · Ingeniería de Sistemas y Computación.
Docente: Carolina Londoño Idárraga.

## Integrantes
- Juan David Martinez
- Santiago Ramirez
- Sebastian Amaya

## Entrega 1 · Modelo y consultas de análisis

### Requisitos
- Oracle Database XE 21c (servicio XEPDB1, puerto 1521)
- Oracle SQL Developer

### Orden de ejecución sobre una base limpia
| Orden | Script | Conexión | Qué hace |
|---|---|---|---|
| 1 | scripts/00_crear_usuario.sql | SYSTEM en XEPDB1 | Crea el esquema TURISMOUQ y sus privilegios |
| 2 | scripts/01_ddl.sql | TURISMOUQ | Elimina y crea tablas, restricciones y comentarios |
| 3 | scripts/02_carga.sql | TURISMOUQ | Carga datos con PL/SQL y DBMS_RANDOM |
| 4 | scripts/03_consultas.sql | TURISMOUQ | Siete consultas de análisis, numeradas y comentadas |

Cada script se ejecuta completo de arriba hacia abajo.

### Documentación
- docs/ contiene el documento con el MER, las reglas de negocio y las decisiones de diseño.
