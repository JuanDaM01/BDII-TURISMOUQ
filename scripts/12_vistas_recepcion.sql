-- 12_vistas_recepcion.sql
-- Proyecto TurismoUQ · Bases de Datos II · Entrega 3 · Seguridad (parte del dueño del esquema)
-- Ejecutar como TURISMOUQ despues de 11_indices.sql y ANTES de 13_seguridad.sql
--
-- Recepcion nunca toca las tablas: todo lo que ve y registra pasa por estas vistas
-- (y por el procedimiento pkg_transacciones.sp_reserva_con_pago para crear reservas).
--   v_rec_habitaciones  habitaciones con su alojamiento, municipio y la tarifa vigente hoy (solo lectura)
--   v_rec_ocupacion     noches ocupadas desde hoy por habitacion, para revisar disponibilidad (solo lectura)
--   v_rec_reservas      reservas vigentes con cliente, total, pagado y saldo (solo lectura)
--   v_rec_clientes      datos de contacto de los clientes; permite registrar y corregir clientes

SET SERVEROUTPUT ON
SET DEFINE OFF


-- SECCION 1: Vistas de recepcion

CREATE OR REPLACE VIEW v_rec_habitaciones AS
SELECT h.id_habitacion,
       a.id_alojamiento,
       a.nombre_comercial    AS alojamiento,
       mu.nombre             AS municipio,
       ta.nombre             AS tipo_alojamiento,
       h.numero,
       h.tipo,
       h.capacidad,
       (SELECT t.valor_noche
          FROM tarifa t
          JOIN temporada te ON te.id_temporada = t.id_temporada
         WHERE t.id_habitacion = h.id_habitacion
           AND TRUNC(SYSDATE) BETWEEN te.fecha_inicio AND te.fecha_fin) AS tarifa_hoy
  FROM habitacion h
  JOIN alojamiento a       ON a.id_alojamiento = h.id_alojamiento
  JOIN municipio mu        ON mu.id_municipio = a.id_municipio
  JOIN tipo_alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
WITH READ ONLY;

CREATE OR REPLACE VIEW v_rec_ocupacion AS
SELECT rh.id_habitacion,
       rh.check_in,
       rh.check_out,
       r.estado
  FROM reserva_habitacion rh
  JOIN reserva r ON r.id_reserva = rh.id_reserva
 WHERE r.estado <> 'CANCELADA'
   AND rh.check_out >= TRUNC(SYSDATE)
WITH READ ONLY;

CREATE OR REPLACE VIEW v_rec_reservas AS
SELECT r.id_reserva,
       c.nombre            AS cliente,
       c.documento,
       a.nombre_comercial  AS alojamiento,
       r.check_in,
       r.check_out,
       r.estado,
       NVL((SELECT SUM(rh.valor_estadia) FROM reserva_habitacion rh WHERE rh.id_reserva = r.id_reserva), 0)
     + NVL((SELECT SUM(rs.cantidad * rs.precio_unitario) FROM reserva_servicio rs WHERE rs.id_reserva = r.id_reserva), 0)
                           AS valor_total,
       NVL((SELECT SUM(p.monto) FROM pago p WHERE p.id_reserva = r.id_reserva AND p.estado = 'EXITOSO'), 0)
                           AS pagado
  FROM reserva r
  JOIN cliente c     ON c.id_cliente = r.id_cliente
  JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
 WHERE r.estado IN ('PENDIENTE', 'CONFIRMADA')
WITH READ ONLY;

-- Vista simple sobre una sola tabla: Oracle permite INSERT y UPDATE a traves de ella
CREATE OR REPLACE VIEW v_rec_clientes AS
SELECT id_cliente, nombre, documento, correo, telefono, ciudad_origen, fecha_registro
  FROM cliente;

COMMENT ON TABLE v_rec_habitaciones IS 'Recepcion: habitaciones con alojamiento, municipio y tarifa vigente hoy. Solo lectura.';
COMMENT ON TABLE v_rec_ocupacion    IS 'Recepcion: noches ocupadas desde hoy (reservas no canceladas) para revisar disponibilidad. Solo lectura.';
COMMENT ON TABLE v_rec_reservas     IS 'Recepcion: reservas pendientes y confirmadas con valor total y valor pagado. Solo lectura.';
COMMENT ON TABLE v_rec_clientes     IS 'Recepcion: datos de contacto de clientes; permite registrar y corregir clientes.';


-- SECCION 2: Verificacion

SELECT view_name, read_only
  FROM user_views
 WHERE view_name LIKE 'V_REC%'
 ORDER BY view_name;

-- columnas actualizables de v_rec_clientes (todas YES)
SELECT column_name, updatable, insertable
  FROM user_updatable_columns
 WHERE table_name = 'V_REC_CLIENTES'
 ORDER BY column_name;

-- ejemplo de uso: habitaciones de Salento para 2 personas libres del 20 al 23 de enero de 2027
SELECT h.id_habitacion, h.alojamiento, h.numero, h.tipo, h.capacidad, h.tarifa_hoy
  FROM v_rec_habitaciones h
 WHERE h.municipio = 'Salento'
   AND h.capacidad >= 2
   AND NOT EXISTS (SELECT 1
                     FROM v_rec_ocupacion o
                    WHERE o.id_habitacion = h.id_habitacion
                      AND o.check_in  < DATE '2027-01-23'
                      AND o.check_out > DATE '2027-01-20')
 ORDER BY h.tarifa_hoy
 FETCH FIRST 10 ROWS ONLY;
