-- 00_crear_usuario.sql
-- Proyecto TurismoUQ · Bases de Datos II
-- Ejecutar como SYSTEM conectado al servicio XEPDB1

-- Limpieza para poder repetir el script en una base limpia
BEGIN
  EXECUTE IMMEDIATE 'DROP USER turismouq CASCADE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1918 THEN RAISE; END IF;  -- -1918: el usuario no existe
END;
/

-- Esquema del proyecto
CREATE USER turismouq IDENTIFIED BY "TurismoUQ_2026"
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;

-- Privilegios para las Entregas 1 y 2
GRANT CREATE SESSION,
      CREATE TABLE,
      CREATE VIEW,
      CREATE SEQUENCE,
      CREATE PROCEDURE,
      CREATE TRIGGER,
      CREATE MATERIALIZED VIEW,
      CREATE SYNONYM,
      CREATE TYPE
  TO turismouq;