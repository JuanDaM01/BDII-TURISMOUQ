-- 13_seguridad.sql
-- Proyecto TurismoUQ · Bases de Datos II · Entrega 3 · Seguridad
-- Ejecutar como SYSTEM conectado al servicio XEPDB1, despues de 12_vistas_recepcion.sql
--
-- SECCION 1  Limpieza (para poder repetir el script)
-- SECCION 2  Perfil con limites de sesion y de contraseña
-- SECCION 3  Cuatro roles con privilegios diferenciados
--              rol_recepcion           solo vistas v_rec_* y el procedimiento de reserva + pago
--              rol_admin_alojamiento   gestiona habitaciones, tarifas y servicios; consulta reservas y pagos
--              rol_gerente             solo lectura de todo lo de negocio + liquidacion mensual
--              rol_auditor             solo lectura de auditoria, pagos, reservas e historico
-- SECCION 4  Usuarios de prueba, uno por rol, todos con el perfil
-- SECCION 5  Verificacion en el diccionario de datos
--
-- SYSTEM puede otorgar privilegios sobre objetos de TURISMOUQ porque tiene GRANT ANY OBJECT PRIVILEGE.

SET SERVEROUTPUT ON
SET DEFINE OFF


-- SECCION 1: Limpieza

BEGIN
  FOR u IN (SELECT username FROM dba_users
             WHERE username IN ('UQ_RECEPCION', 'UQ_ADMIN_ALOJ', 'UQ_GERENTE', 'UQ_AUDITOR')) LOOP
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;

  FOR r IN (SELECT role FROM dba_roles
             WHERE role IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR')) LOOP
    EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
  END LOOP;

  FOR p IN (SELECT DISTINCT profile FROM dba_profiles WHERE profile = 'PERFIL_TURISMOUQ') LOOP
    EXECUTE IMMEDIATE 'DROP PROFILE perfil_turismouq CASCADE';
  END LOOP;
END;
/


-- SECCION 2: Perfil
-- SESSIONS_PER_USER 2        un empleado no necesita mas de dos sesiones abiertas a la vez
-- IDLE_TIME 10               una sesion inactiva 10 minutos se cierra (equipo de recepcion desatendido)
-- CONNECT_TIME 600           ninguna sesion dura mas de un turno de 10 horas
-- FAILED_LOGIN_ATTEMPTS 3    tres claves equivocadas bloquean la cuenta
-- PASSWORD_LOCK_TIME 1/1440  el bloqueo dura 1 minuto (corto para poder demostrarlo; en produccion 1 dia)
-- PASSWORD_LIFE_TIME 90      la clave vence a los 90 dias, con 7 de gracia
-- Los limites de recursos (SESSIONS_PER_USER, IDLE_TIME, CONNECT_TIME) solo se aplican con
-- RESOURCE_LIMIT = TRUE, que es el valor por defecto desde Oracle 12c (se verifica abajo).

CREATE PROFILE perfil_turismouq LIMIT
  SESSIONS_PER_USER      2
  IDLE_TIME              10
  CONNECT_TIME           600
  FAILED_LOGIN_ATTEMPTS  3
  PASSWORD_LOCK_TIME     1/1440
  PASSWORD_LIFE_TIME     90
  PASSWORD_GRACE_TIME    7;


-- SECCION 3: Roles y privilegios

CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_alojamiento;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

GRANT CREATE SESSION TO rol_recepcion, rol_admin_alojamiento, rol_gerente, rol_auditor;

-- otorgar: concede el privilegio solo si el objeto existe y avisa si no
-- (asi el script no se cae si se ejecuta en un orden distinto)
DECLARE
  PROCEDURE otorgar (p_priv VARCHAR2, p_objeto VARCHAR2, p_rol VARCHAR2) IS
    v_existe NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_existe
      FROM dba_objects
     WHERE owner = 'TURISMOUQ'
       AND object_name = UPPER(p_objeto)
       AND object_type IN ('TABLE', 'VIEW', 'PACKAGE', 'MATERIALIZED VIEW');
    IF v_existe > 0 THEN
      EXECUTE IMMEDIATE 'GRANT ' || p_priv || ' ON turismouq.' || p_objeto || ' TO ' || p_rol;
    ELSE
      DBMS_OUTPUT.PUT_LINE('AVISO: no existe TURISMOUQ.' || UPPER(p_objeto) || ', no se otorgó a ' || p_rol);
    END IF;
  END otorgar;
BEGIN
  -- RECEPCION: solo vistas. Lee habitaciones, ocupacion y reservas; registra y corrige clientes;
  -- crea reservas unicamente con el procedimiento atomico de reserva + pago
  otorgar('SELECT',                  'v_rec_habitaciones', 'rol_recepcion');
  otorgar('SELECT',                  'v_rec_ocupacion',    'rol_recepcion');
  otorgar('SELECT',                  'v_rec_reservas',     'rol_recepcion');
  otorgar('SELECT, INSERT',          'v_rec_clientes',     'rol_recepcion');
  otorgar('UPDATE (correo, telefono)', 'v_rec_clientes',   'rol_recepcion');
  otorgar('EXECUTE',                 'pkg_transacciones',  'rol_recepcion');

  -- ADMINISTRADOR DE ALOJAMIENTO: gestiona su oferta (habitaciones, tarifas, servicios),
  -- cambia el estado de las reservas y consulta pagos. No borra nada ni ve la auditoria.
  otorgar('SELECT, INSERT, UPDATE', 'habitacion', 'rol_admin_alojamiento');
  otorgar('SELECT, INSERT, UPDATE', 'tarifa',     'rol_admin_alojamiento');
  otorgar('SELECT, INSERT, UPDATE', 'servicio',   'rol_admin_alojamiento');
  otorgar('SELECT',                 'alojamiento',      'rol_admin_alojamiento');
  otorgar('SELECT',                 'temporada',        'rol_admin_alojamiento');
  otorgar('SELECT',                 'municipio',        'rol_admin_alojamiento');
  otorgar('SELECT',                 'tipo_alojamiento', 'rol_admin_alojamiento');
  otorgar('SELECT, UPDATE (estado, fecha_cancelacion)', 'reserva', 'rol_admin_alojamiento');
  otorgar('SELECT',                 'reserva_habitacion', 'rol_admin_alojamiento');
  otorgar('SELECT',                 'reserva_servicio',   'rol_admin_alojamiento');
  otorgar('SELECT',                 'pago',               'rol_admin_alojamiento');
  otorgar('SELECT',                 'cliente',            'rol_admin_alojamiento');
  otorgar('EXECUTE',                'pkg_reservas',       'rol_admin_alojamiento');

  -- GERENTE: lectura de todo lo de negocio para los analisis y la liquidacion mensual. Sin DML.
  FOR t IN (SELECT column_value AS tabla
              FROM TABLE(sys.odcivarchar2list(
                     'municipio', 'tipo_alojamiento', 'alojamiento', 'habitacion', 'temporada',
                     'tarifa', 'cliente', 'reserva', 'reserva_habitacion', 'pago', 'servicio',
                     'reserva_servicio', 'resena', 'liquidacion_mensual', 'mv_ocupacion_mensual',
                     'reserva_historico'))) LOOP
    otorgar('SELECT', t.tabla, 'rol_gerente');
  END LOOP;
  otorgar('EXECUTE', 'pkg_reservas', 'rol_gerente');

  -- AUDITOR: solo lectura de lo que permite rastrear cambios y dinero. No modifica nada.
  FOR t IN (SELECT column_value AS tabla
              FROM TABLE(sys.odcivarchar2list(
                     'tarifa_auditoria', 'tarifa', 'pago', 'reserva', 'reserva_historico',
                     'liquidacion_mensual', 'usuario_sistema', 'rol'))) LOOP
    otorgar('SELECT', t.tabla, 'rol_auditor');
  END LOOP;
END;
/


-- SECCION 4: Usuarios de prueba (uno por rol), todos con el perfil
-- Sin cuota en ningun tablespace: no pueden crear objetos propios.

CREATE USER uq_recepcion  IDENTIFIED BY "Recepcion_2026" PROFILE perfil_turismouq
  DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER uq_admin_aloj IDENTIFIED BY "AdminAloj_2026" PROFILE perfil_turismouq
  DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER uq_gerente    IDENTIFIED BY "Gerente_2026"   PROFILE perfil_turismouq
  DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER uq_auditor    IDENTIFIED BY "Auditor_2026"   PROFILE perfil_turismouq
  DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;

GRANT rol_recepcion         TO uq_recepcion;
GRANT rol_admin_alojamiento TO uq_admin_aloj;
GRANT rol_gerente           TO uq_gerente;
GRANT rol_auditor           TO uq_auditor;


-- SECCION 5: Verificacion

-- RESOURCE_LIMIT debe estar en TRUE para que se apliquen los limites de sesion
SELECT name, value FROM v$parameter WHERE name = 'resource_limit';

-- limites del perfil
SELECT resource_name, limit
  FROM dba_profiles
 WHERE profile = 'PERFIL_TURISMOUQ'
   AND resource_name IN ('SESSIONS_PER_USER', 'IDLE_TIME', 'CONNECT_TIME', 'FAILED_LOGIN_ATTEMPTS',
                         'PASSWORD_LOCK_TIME', 'PASSWORD_LIFE_TIME', 'PASSWORD_GRACE_TIME')
 ORDER BY resource_name;

-- usuarios, su perfil y su rol
SELECT u.username, u.profile, u.account_status, rp.granted_role
  FROM dba_users u
  JOIN dba_role_privs rp ON rp.grantee = u.username
 WHERE u.username LIKE 'UQ\_%' ESCAPE '\'
 ORDER BY u.username;

-- privilegios de objeto por rol (recepcion solo tiene vistas V_REC_* y el paquete)
SELECT grantee AS rol, table_name AS objeto,
       LISTAGG(privilege, ', ') WITHIN GROUP (ORDER BY privilege) AS privilegios
  FROM dba_tab_privs
 WHERE grantee IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR')
   AND owner = 'TURISMOUQ'
 GROUP BY grantee, table_name
 ORDER BY grantee, table_name;

-- privilegios por columna (UPDATE limitado a ciertas columnas)
SELECT grantee AS rol, table_name AS objeto, column_name, privilege
  FROM dba_col_privs
 WHERE grantee IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO')
   AND owner = 'TURISMOUQ'
 ORDER BY grantee, table_name, column_name;
