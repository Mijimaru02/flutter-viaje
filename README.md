# Viaje en Común

Aplicación Flutter para organizar viajes compartidos con Supabase Auth, PostgreSQL, Storage privado y Realtime.

## Módulos

- `lib/features/auth`: registro, inicio/cierre de sesión y recuperación de contraseña.
- `lib/features/trips`: lista, creación, archivo/reactivación, miembros e invitaciones.
- `lib/features/itinerary`: agenda por días, edición por rol/autor, filtros y Supabase Realtime.
- `lib/features/expenses`: gastos, reparto igualitario/personalizado y balances calculados en céntimos.
- `lib/features/documents`: subida, consulta y eliminación de documentos en un bucket privado.
- `supabase/migrations`: esquema, funciones transaccionales, RLS y políticas de Storage.

La app usa `setState` y `Navigator` de Flutter; no incorpora un framework externo de estado o rutas. La lógica monetaria está en `lib/features/expenses/expense_calculator.dart` y se puede probar sin iniciar la interfaz.

## Configuración de Supabase

1. Crea un proyecto Supabase y habilita Auth con correo y contraseña. En proyectos con confirmación de correo, verifica cada cuenta antes de iniciar sesión.
   Configura la URL del sitio y las redirecciones permitidas de Auth: el origen web usado por la app y `com.example.viajeencomun://reset-callback` para Android/iOS. El enlace abre la pantalla de nueva contraseña. Si cambias el identificador de paquete, actualiza también este esquema en Android, iOS y Auth.
2. Ejecuta el contenido de `supabase/migrations/20261126180800_initial_schema.sql` en el SQL Editor del proyecto. La migración crea las tablas, las restricciones, las funciones transaccionales, las políticas RLS y el bucket privado `trip-documents`.
3. Para cargar datos de demostración, crea en Auth estas cuentas y completa sus perfiles:
   - `lucia@viaje.test` — propietaria
   - `ana@viaje.test` — editora
   - `marcos@viaje.test` — lector
   
   Después ejecuta `supabase/seed.sql` en el SQL Editor. El seed crea un viaje compartido (incluye el ejemplo de balance), otro viaje privado y una actividad. Las contraseñas las establece cada usuario durante el registro y no se guardan en el repositorio.
4. Copia la URL del proyecto y la clave publicable desde el Dashboard. No uses `service_role`, claves secretas ni contraseñas en Flutter.

El esquema asocia pagador, creador y participantes a miembros del mismo viaje mediante claves foráneas compuestas. La aceptación de invitaciones y el guardado de gasto/repartos se ejecutan en funciones PostgreSQL; el token de invitación se almacena como hash. Las políticas RLS aplican roles y autoría también si se llama a la API sin pasar por Flutter. El bucket no es público y sus políticas limitan lectura, subida y borrado por viaje/rol.

## Ejecutar

Desde `DI_UD1/viajeencomun`:

```powershell
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

En Windows, Flutter puede requerir activar **Developer Mode** para crear enlaces simbólicos al compilar plugins. No compartas la clave de proyecto en capturas o repositorios públicos.

## Pruebas

```powershell
flutter test
flutter analyze
```

Las pruebas unitarias cubren el reparto por céntimos (incluido el orden del sobrante), el rechazo de un reparto personalizado que no suma el total y los balances del ejemplo.

## Demostración manual con dos sesiones

1. Inicia sesión como Lucía y crea un viaje; comprueba que aparece como propietaria.
2. Crea una invitación para Ana como editora y usa el código en la sesión de Ana. Intenta el mismo código con Marcos para comprobar que solo sirve para el correo invitado.
3. Abre la agenda en dos sesiones y añade/edita una actividad como Ana; verifica que la otra sesión se actualiza.
4. Comprueba que Marcos, como lector, no puede modificar la actividad y que la petición directa contra Supabase es rechazada.
5. Introduce los gastos de alojamiento y transporte del ejemplo; comprueba el total de 150,00 € y los saldos +80,00 €, −25,00 € y −55,00 €.
6. Sube y abre un PDF o imagen como miembro. Intenta descargarlo desde una cuenta que no pertenece al viaje y verifica el rechazo.
7. Archiva el viaje como Lucía y confirma que una escritura iniciada desde otra sesión ya no se acepta. Reactívalo para continuar.

Las comprobaciones de RLS y Storage deben ejecutarse contra el proyecto Supabase configurado; los tests locales no sustituyen esa verificación.

### Comprobaciones reproducibles de autorización

1. Crea una cuenta ajena al viaje. Como propietaria, copia el `id` de una actividad y el `storage_path` de un documento de demostración.
2. Inicia una sesión Flutter como Marcos (lector) y ejecuta una escritura directa con el cliente, sin pasar por la UI:

   ```dart
   final rows = await Supabase.instance.client
       .from('activities')
       .update({'title': 'Este cambio debe rechazarse'})
       .eq('id', '<activity-id>')
       .select('id');
   assert(rows.isEmpty);
   ```

   El `UPDATE` debe afectar cero filas por RLS; vuelve a consultar como propietaria y comprueba que el título no cambió.
3. Inicia sesión con la cuenta ajena y prueba la ruta conocida del archivo:

   ```dart
   await Supabase.instance.client.storage
       .from('trip-documents')
       .createSignedUrl('<storage_path>', 60);
   ```

   La llamada debe fallar por la política de Storage. Como miembro del viaje, la misma operación debe devolver una URL temporal.
