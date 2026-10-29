SET SERVEROUTPUT ON
SET DEFINE OFF


-- SECCION 1: Historico de reservas
-- Copia las reservas cerradas (COMPLETADA o CANCELADA) con check-out anterior a 2026,
-- con el valor total de sus estadias. Se copian y no se mueven para que las consultas
-- de la Entrega 1 sigan leyendo 2024 y 2025 en RESERVA.
-- Sin llaves foraneas: el historico debe sobrevivir a cambios en los maestros.

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE reserva_historico PURGE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -942 THEN RAISE; END IF;  -- -942: la tabla no existe
END;
/

CREATE TABLE reserva_historico (
  id_reserva         NUMBER        NOT NULL,
  id_cliente         NUMBER        NOT NULL,
  id_alojamiento     NUMBER        NOT NULL,
  fecha_reserva      DATE          NOT NULL,
  check_in           DATE          NOT NULL,
  check_out          DATE          NOT NULL,
  estado             VARCHAR2(10)  NOT NULL,
  fecha_cancelacion  DATE,
  valor_estadias     NUMBER(14,2)  NOT NULL,
  fecha_archivo      DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_reserva_historico PRIMARY KEY (id_reserva)
             USING INDEX TABLESPACE ts_historico_reservas,
  CONSTRAINT ck_reshist_estado CHECK (estado IN ('COMPLETADA','CANCELADA')),
  CONSTRAINT ck_reshist_fechas CHECK (check_out > check_in)
) TABLESPACE ts_historico_reservas;

COMMENT ON TABLE reserva_historico IS 'Historico de reservas cerradas de años anteriores, guardado en el tablespace TS_HISTORICO_RESERVAS.';
COMMENT ON COLUMN reserva_historico.valor_estadias IS 'Suma del valor_estadia de las lineas de habitacion de la reserva.';
COMMENT ON COLUMN reserva_historico.fecha_archivo IS 'Fecha en que la reserva se copio al historico.';

INSERT INTO reserva_historico (id_reserva, id_cliente, id_alojamiento, fecha_reserva,
                               check_in, check_out, estado, fecha_cancelacion, valor_estadias)
SELECT r.id_reserva, r.id_cliente, r.id_alojamiento, r.fecha_reserva,
       r.check_in, r.check_out, r.estado, r.fecha_cancelacion,
       NVL(SUM(rh.valor_estadia), 0)
  FROM reserva r
  LEFT JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
 WHERE r.estado IN ('COMPLETADA', 'CANCELADA')
   AND r.check_out < DATE '2026-01-01'
 GROUP BY r.id_reserva, r.id_cliente, r.id_alojamiento, r.fecha_reserva,
          r.check_in, r.check_out, r.estado, r.fecha_cancelacion;

COMMIT;


-- SECCION 2: Vista materializada de ocupacion mensual
-- Una fila por alojamiento, año y mes. Mismo criterio de la consulta 1 de la Entrega 1:
-- no cuenta las reservas canceladas y asigna cada linea al mes de su check-in.
--
-- Refresco: COMPLETE ON DEMAND
--  * no es ON COMMIT porque cada reserva nueva obligaria a recalcular la vista y frenaria el registro de reservas
--  * no es FAST porque exige logs sobre RESERVA y RESERVA_HABITACION, que agregan trabajo a cada escritura,
--    y la vista es pequeña (60 alojamientos por 36 meses como maximo) y se reconstruye en segundos
--  * se refresca una vez al dia fuera del horario de operacion, despues de una carga masiva
--    y al cerrar el mes antes de la liquidacion
--  * puede quedar desactualizada hasta el siguiente refresco, algo aceptable para un indicador mensual

BEGIN
  EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_ocupacion_mensual';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -12003 THEN RAISE; END IF;  -- -12003: la vista materializada no existe
END;
/

CREATE MATERIALIZED VIEW mv_ocupacion_mensual
  BUILD IMMEDIATE
  REFRESH COMPLETE ON DEMAND
AS
SELECT rh.id_alojamiento,
       EXTRACT(YEAR  FROM rh.check_in) AS anio,
       EXTRACT(MONTH FROM rh.check_in) AS mes,
       SUM(rh.check_out - rh.check_in) AS noches_ocupadas,
       COUNT(*)                        AS lineas_habitacion,
       COUNT(DISTINCT rh.id_reserva)   AS reservas
  FROM reserva_habitacion rh
  JOIN reserva r ON r.id_reserva = rh.id_reserva
 WHERE r.estado <> 'CANCELADA'
 GROUP BY rh.id_alojamiento,
          EXTRACT(YEAR  FROM rh.check_in),
          EXTRACT(MONTH FROM rh.check_in);

COMMENT ON MATERIALIZED VIEW mv_ocupacion_mensual IS 'Ocupacion mensual por alojamiento (noches, lineas y reservas no canceladas, por mes de check-in). Refresco COMPLETE ON DEMAND.';


-- SECCION 3: Verificacion

-- tabla e indice del historico en TS_HISTORICO_RESERVAS
SELECT segment_name, segment_type, tablespace_name
  FROM user_segments
 WHERE segment_name IN ('RESERVA_HISTORICO', 'PK_RESERVA_HISTORICO')
 ORDER BY segment_name;

-- reservas archivadas (solo 2024 y 2025)
SELECT COUNT(*) AS reservas_archivadas, MIN(check_in) AS primer_check_in, MAX(check_out) AS ultimo_check_out
  FROM reserva_historico;

-- modo y metodo de refresco de la vista
SELECT mview_name, refresh_mode, refresh_method, build_mode, last_refresh_date
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';

SELECT COUNT(*) AS filas_vista FROM mv_ocupacion_mensual;

SELECT *
  FROM mv_ocupacion_mensual
 ORDER BY anio, mes, id_alojamiento
 FETCH FIRST 10 ROWS ONLY;
