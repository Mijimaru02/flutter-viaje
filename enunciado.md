Enunciado de proyecto: Viaje en Común

Viaje en Común es una aplicación móvil para organizar viajes en grupo. Los viajeros podrán preparar un itinerario compartido, registrar gastos, consultar cuánto debe aportar cada persona y guardar documentos del viaje. La aplicación se desarrollará con Flutter y utilizará Supabase para la autenticación, la base de datos PostgreSQL, el almacenamiento privado de archivos y la sincronización del itinerario.

El proyecto está planteado como un trabajo de nivel intermedio–avanzado. Puedes realizarlo individualmente o en un equipo de dos personas. El resultado debe poder demostrarse con varias cuentas y dispositivos, desde la creación de un viaje hasta la consulta del balance final.

1. Situación de partida

Lucía está organizando una escapada a Lisboa con Ana y Marcos. Las reservas están repartidas entre varios correos, los horarios se acuerdan en un chat y cada persona apunta sus gastos donde puede. Antes de salir, el grupo necesita consultar la versión actual del plan. Durante el viaje, necesita saber quién pagó cada compra y a quién le corresponde.

Lucía creará un viaje en la aplicación e invitará a sus amigos. Ana se encargará de completar el itinerario y Marcos registrará los gastos que pague. Si cambian la hora de una actividad mientras los tres tienen abierta la aplicación, la agenda se actualizará en sus dispositivos. Al terminar, podrán consultar las cuentas y conservar el viaje archivado.

2. Objetivos del proyecto

- Construir una aplicación móvil con varios flujos completos y estados de carga, error y recuperación.
- Modelar en PostgreSQL un dominio con usuarios, viajes, miembros, actividades, gastos, repartos y documentos.
- Aplicar permisos por viaje mediante Row Level Security (RLS) y comprobarlos desde Supabase.
- Implementar operaciones que mantienen varios registros consistentes, como aceptar una invitación o guardar un gasto con su reparto.
- Verificar que dos usuarios pueden trabajar sobre el mismo viaje desde dispositivos distintos.

3. Usuarios y permisos

Una cuenta puede participar en varios viajes con permisos diferentes en cada uno. Por ejemplo, Ana puede ser editora del viaje a Lisboa y propietaria de otro viaje a Roma.
Acción                                              Propietario         Editor               Lector
Consultar el viaje, sus miembros y su contenido     Sí                  Sí                   Sí
Crear actividades, gastos y documentos              Sí                  Sí                   No
Editar o eliminar actividades, gastos y documentos 	Cualquier elemento  Los que haya creado  Ninguno
Editar los datos generales del viaje                Sí                  No                   No
Crear o revocar invitaciones                        Sí                  No                   No
Cambiar el rol de otro miembro                      Sí                  No                   No
Archivar o reactivar el viaje                       Sí                  No                   No

La creación de un viaje asignará el rol de propietario a su creador. Los roles disponibles al invitar a otra persona serán editor y lector. Cualquier miembro, incluido un lector, podrá figurar en el reparto de un gasto. Así, una persona puede consultar lo que debe sin tener permiso para modificar las cuentas.

Flutter mostrará las acciones disponibles para cada usuario. Supabase aplicará las mismas reglas cuando reciba una petición directa, incluso si alguien modifica la aplicación o utiliza otro cliente.

4. Requisitos funcionales
4.1. Registro, inicio de sesión y perfil

La aplicación permitirá crear una cuenta con correo y contraseña, iniciar y cerrar sesión, y recuperar el acceso mediante correo. El perfil incluirá un nombre visible para los compañeros de viaje.

Al abrir la aplicación con una sesión válida, el usuario llegará a Mis viajes. Si la sesión ha caducado durante una operación, la aplicación mostrará el motivo y ofrecerá volver a identificarse. El cierre de sesión debe limpiar del estado de la aplicación y los datos de la cuenta anterior.

4.2. Creación y gestión de viajes

El formulario de creación incluirá título, destino, fecha de inicio, fecha de fin y una descripción opcional. Todos los importes del proyecto se expresarán en euros. Las fechas y horas del itinerario se introducirán según la hora local del destino.

En Mis viajes, el usuario verá los viajes en los que participa, ordenados por fecha de inicio, y podrá consultar los archivados en una sección propia. La tarjeta de cada viaje mostrará su nombre, destino, fechas y el rol del usuario. La ficha del viaje dará acceso a la agenda, los gastos, los documentos y los miembros.

El propietario podrá archivar el viaje. Mientras esté archivado, sus miembros conservarán el acceso de lectura y el propietario podrá reactivarlo. Las operaciones de escritura, incluida la aceptación de invitaciones, deberán respetar ese estado. Si el propietario cambia las fechas, el sistema rechazará el cambio cuando deje actividades existentes fuera del nuevo intervalo.

4.3. Invitaciones y miembros

El propietario indicará el correo del invitado y su rol. La aplicación generará una invitación de un solo uso y mostrará un código o enlace que el propietario pueda compartir. Para completar la incorporación, el destinatario deberá iniciar sesión con la cuenta correspondiente al correo invitado.

Las invitaciones tendrán una validez de siete días. El propietario podrá consultar su estado y revocar las pendientes. La aplicación distinguirá entre una invitación caducada, una revocada y una que pertenece a otra cuenta. Al aceptar una invitación, Supabase deberá registrar la incorporación y el uso de la invitación en una misma operación. Repetir la petición con la cuenta que ya la aceptó devolverá el estado de incorporación existente sin duplicar al miembro.

Una vez incorporado el usuario, el propietario podrá cambiar su rol entre editor y lector. El permiso actualizado deberá aplicarse al siguiente intento de escritura, aunque el otro usuario todavía tenga abierta una pantalla con los permisos anteriores.

4.4. Itinerario compartido

La agenda se mostrará agrupada por días y ordenada por hora. Una actividad tendrá título, fecha, hora de inicio, categoría y, opcionalmente, hora de fin, dirección y notas. Las categorías iniciales serán transporte, alojamiento, comida, visita y tiempo libre.

El propietario y los editores podrán crear actividades. Se preservará el autor de cada una para aplicar los permisos de edición y eliminación. La fecha deberá estar dentro del viaje y, cuando se indique una hora de fin, tendrá que ser posterior a la de inicio. Cada actividad corresponderá a un solo día.

La agenda incorporará un filtro por categoría y un estado vacío que indicará el día seleccionado. También deberá actualizarse mediante Supabase Realtime cuando otra persona añada, edite o elimine una actividad. Al recuperar la conexión o volver a la pantalla, la aplicación volverá a consultar la agenda para reflejar los cambios que hayan ocurrido mientras estaba desconectada.
4.5. Gastos compartidos

Cada gasto incluirá un concepto, un importe positivo, una fecha, una categoría, la persona que pagó y los miembros entre los que se reparte. La persona que registra el gasto puede ser distinta de quien lo pagó. Los miembros seleccionados deberán pertenecer al mismo viaje.

Habrá dos modalidades de reparto:

- A partes iguales. El sistema divide el importe entre las personas seleccionadas. Si sobran céntimos, los asigna de uno en uno siguiendo el orden en que se seleccionaron los participantes. La vista previa mostrará el importe exacto de cada persona.
- Por importes personalizados. El usuario introduce lo que corresponde a cada participante. El formulario solo permite guardar cuando la suma coincide con el total del gasto.

Los importes se guardarán en céntimos enteros. El gasto y sus repartos se crearán o actualizarán juntos. Si falla la validación de un reparto, la operación completa debe conservar el estado anterior. La aplicación permitirá consultar el detalle de un gasto y filtrar la lista por categoría o por persona que pagó.

La pantalla de resumen mostrará el gasto total registrado y, para cada miembro, cuánto ha pagado, cuánto le corresponde y su saldo. El saldo se calcula como importe pagado menos importe asignado. Un valor positivo indica que esa persona debe recibir dinero y uno negativo indica que debe aportarlo. La suma de todos los saldos debe ser exactamente cero.

Ejemplo de referencia

Ana registra un alojamiento de 120 € que pagó ella y reparte entre tres personas. Marcos registra un transporte de 30 € que pagó él y que se reparte por igual entre Marcos y Lucía.
Miembro 	Ha pagado 	Le corresponde 	Saldo
Ana         120,00 €    40,00 €         +80,00 €
Marcos      30,00 €     55,00 €         −25,00 €
Lucía       0,00 €      55,00 €         −55,00 €
Total       150,00 €    150,00 €        0,00 €
4.6. Documentos privados

Cada viaje tendrá una sección para guardar reservas, billetes, entradas u otros archivos. El propietario y los editores podrán subir documentos en PDF, JPEG o PNG de hasta 10 MB. Cada documento tendrá un título visible, un autor y una fecha de subida.

Los archivos se almacenarán en un bucket privado de Supabase Storage. Solo los miembros del viaje podrán abrirlos o descargarlos. Los permisos de eliminación seguirán la tabla de roles.

Durante la subida, la interfaz mostrará el progreso. Un documento aparecerá como disponible cuando se hayan guardado el archivo y sus datos. Si la operación falla a mitad, el flujo deberá permitir reintentar y evitar que queden entradas visibles que apunten a archivos inexistentes.
5. Modelo de datos propuesto

Se pueden adaptar los nombres y la estructura. La entrega debe explicar las relaciones, las restricciones de integridad y cómo se aplican los permisos.
Tabla             Finalidad 	                                  Campos orientativos
profiles          Perfil asociado a la cuenta 	                  id, display_name
trips             Información general y estado del viaje          id, title, destination, start_date, end_date, description, archived_at
trip_members      Participantes y roles por viaje                 trip_id, user_id, role, joined_at
trip_invitations  Invitaciones, caducidad y uso                   id, trip_id, email, role, token_hash, expires_at, used_at, revoked_at
activities        Elementos de la agenda                          id, trip_id, created_by, title, date, start_time, end_time, category, address, notes
expenses          Gastos realizados                               id, trip_id, created_by, paid_by, title, amount_cents, date, category
expense_splits    Parte del gasto que corresponde a cada persona  expense_id, user_id, amount_cents
trip_documents    Metadatos de los archivos privados              id, trip_id, created_by, title, storage_path, mime_type, size_bytes, created_at

Como mínimo, el diseño deberá impedir que una cuenta aparezca dos veces como miembro del mismo viaje o dos veces en el reparto de un gasto. También deberá comprobar que el pagador y los participantes del reparto pertenecen al viaje del gasto.

Crear un viaje con su propietario, aceptar una invitación y guardar un gasto con sus repartos son operaciones que deberán ser atómicas en PostgreSQL. Puedes implementarlas mediante funciones de base de datos llamadas desde Flutter. Cada función deberá validar los permisos y datos de la cuenta que la ejecuta.

6. Requisitos técnicos y de interfaz

Flutter

- Organizar el código de modo que la lógica de reparto y saldo pueda probarse sin iniciar la interfaz. La elección de la solución de estado y navegación queda abierta.
- Implementar formularios con validación y mensajes junto al campo que se debe corregir.
- Representar los estados de carga, lista vacía, error y conexión recuperada en los flujos principales.
- Evitar que pulsar varias veces el botón de envío duplique una invitación, un gasto o una subida.
- Probar el diseño en dos tamaños de pantalla y comprobar que los formularios se pueden completar con el teclado abierto.
- Mostrar fechas e importes en formato español. Usar etiquetas como «Debe aportar», «Debe recibir» y «Al día» para que el saldo se entienda también sin distinguir los colores.

Supabase

- Utilizar Auth, PostgreSQL, Storage y Realtime en los flujos definidos.
- Versionar mediante migraciones las tablas, restricciones, funciones y políticas necesarias para levantar el proyecto desde cero.
- Activar RLS en las tablas expuestas a la aplicación y aplicar políticas de almacenamiento vinculadas a la pertenencia al viaje.
- Configurar Flutter con la URL del proyecto y su clave publicable. Las claves con privilegios elevados deberán permanecer fuera de la app y del repositorio.
- Preparar datos de demostración con un viaje compartido, al menos otro viaje privado y cuentas con roles distintos.

7. Criterios de aceptación
Escenario                                                                           Resultado esperado
Lucía crea «Escapada a Lisboa»                                                      El viaje aparece en su lista y su cuenta queda registrada como propietaria.
Marcos introduce un código emitido para el correo de Ana                            La incorporación se rechaza y la invitación sigue disponible para Ana.
Ana acepta la invitación desde dos dispositivos casi a la vez                       Se crea una sola membresía y ambos dispositivos pueden mostrar que Ana ya está incorporada.
Ana, como editora, añade una visita                                                 Lucía ve la visita en la agenda abierta en otro dispositivo sin recargar manualmente.
Marcos, como lector, intenta actualizar una actividad directamente contra Supabase  La petición se rechaza y la actividad conserva sus datos.
Se reparte un gasto de 10,00 € entre tres personas                                  Se guardan 3,34 €, 3,33 € y 3,33 €, según el orden de selección.
Se intenta guardar un gasto de 20,00 € con un reparto de 19,99 €                    La operación se rechaza y no queda ningún registro parcial.
Se introducen los gastos del ejemplo de Lisboa                                      El total es 150,00 € y los saldos de Ana, Marcos y Lucía son +80,00 €, −25,00 € y −55,00 €, respectivamente.
Una cuenta ajena al viaje intenta descargar un billete                              El acceso se rechaza aunque conozca la ruta del archivo.
Lucía archiva el viaje mientras Ana tiene abierto un formulario de actividad        Ana recibe un mensaje al intentar guardar y el itinerario permanece intacto.

8. Entrega y demostración

La entrega incluirá el repositorio Flutter, las migraciones SQL, un README de instalación, los datos de demostración y las pruebas. El README explicará cómo configurar Supabase, ejecutar las migraciones, preparar las cuentas de prueba y arrancar la aplicación. Incorporará un esquema breve del modelo de datos y las decisiones relevantes sobre permisos y sincronización.

Las pruebas deberán cubrir el cálculo de saldos, el reparto con redondeo y el rechazo de importes incorrectos. Además, la validación debe incluir al menos un caso de escritura sin permisos y uno de acceso a un archivo privado por parte de una cuenta ajena al viaje. Estas comprobaciones pueden formar parte de una suite de integración o acompañarse de pasos reproducibles y resultados esperados.

En la demostración se utilizarán dos sesiones abiertas a la vez. El recorrido empezará con la creación de un viaje y la aceptación de una invitación. Después se modificará una actividad para observar su actualización en la segunda sesión, se registrará un gasto y se comprobará el balance. El cierre de la demo mostrará el acceso legítimo a un documento y el rechazo de un acceso desde otra cuenta.

Rúbrica de evaluación
Criterio                                                               Peso
Flujos completos de viajes, invitaciones, agenda, gastos y documentos  30 %
Autorización por roles y privacidad de datos y archivos                25 %
Integridad del modelo, transacciones y exactitud del reparto           20 %
Usabilidad de la aplicación y gestión de errores                       15 %
Pruebas, documentación y reproducibilidad de la entrega                10 %

9. Ampliaciones opcionales

Una vez completados los criterios de aceptación, puedes elegir una ampliación:

- Liquidación de saldos. Proponer quién debería pagar a quién, permitir registrar transferencias realizadas y recalcular el saldo pendiente.
- Consulta sin conexión. Guardar localmente la última agenda y señalar cuándo se sincronizó por última vez.
- Encuestas. Permitir que el grupo vote entre varias actividades antes de incorporar la ganadora al itinerario.
- Exportación de gastos. Generar un CSV con los gastos, sus participantes y el resumen de saldos.
- Recordatorios de viaje. Programar avisos antes de actividades marcadas como importantes y actualizarlos si cambia la hora.

El proyecto se considera completo cuando un grupo puede organizar y cerrar un viaje realista, sus miembros ven los datos que les corresponden y el balance coincide al céntimo con los gastos registrados.