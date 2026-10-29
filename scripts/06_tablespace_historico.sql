SET SERVEROUTPUT ON
SET DEFINE OFF


-- SECCION 1: Tablespace del historico de reservas
-- Se separa del tablespace USERS por cuatro razones:
--  * crece por su cuenta (las reservas cerradas solo se agregan) y no compite por espacio con las tablas operativas
--  * su archivo puede ir en otro disco, asi las consultas historicas no pelean la E/S con las reservas en curso
--  * los datos operativos se respaldan seguido y el historico, que no cambia, se puede respaldar menos o dejar en solo lectura
--  * se le puede fijar un tamaño maximo y una cuota propia

DECLARE
  v_existe NUMBER;
  v_dir    VARCHAR2(500);
BEGIN
  SELECT COUNT(*) INTO v_existe
    FROM dba_tablespaces
   WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';

  IF v_existe > 0 THEN
    EXECUTE IMMEDIATE 'DROP TABLESPACE ts_historico_reservas INCLUDING CONTENTS AND DATAFILES CASCADE CONSTRAINTS';
  END IF;

  -- el archivo se crea en la misma carpeta que los de USERS (sirve en Windows y en Linux)
  SELECT SUBSTR(file_name, 1, GREATEST(INSTR(file_name, '/', -1), INSTR(file_name, '\', -1)))
    INTO v_dir
    FROM dba_data_files
   WHERE tablespace_name = 'USERS'
     AND ROWNUM = 1;

  EXECUTE IMMEDIATE
    'CREATE TABLESPACE ts_historico_reservas ' ||
    'DATAFILE ''' || v_dir || 'ts_historico_reservas01.dbf'' ' ||
    'SIZE 50M AUTOEXTEND ON NEXT 10M MAXSIZE 500M ' ||
    'EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO';

  EXECUTE IMMEDIATE 'ALTER USER turismouq QUOTA UNLIMITED ON ts_historico_reservas';

  DBMS_OUTPUT.PUT_LINE('Tablespace TS_HISTORICO_RESERVAS creado en ' || v_dir);
END;
/


-- SECCION 2: Verificacion

-- debe aparecer ONLINE, PERMANENT, LOCAL y AUTO
SELECT tablespace_name, status, contents, extent_management, segment_space_management
  FROM dba_tablespaces
 WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';

-- archivo de datos: 50 MB iniciales, crece de 10 en 10 hasta 500 MB
SELECT file_name, ROUND(bytes / 1024 / 1024) AS mb, autoextensible,
       ROUND(maxbytes / 1024 / 1024) AS max_mb
  FROM dba_data_files
 WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';

-- cuota de TURISMOUQ (max_bytes = -1 es ilimitada)
SELECT username, tablespace_name, max_bytes
  FROM dba_ts_quotas
 WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';
