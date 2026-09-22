# Ballasted-track input controls

In the dispatch console, select **Data input / Keyboard** before launching the
ballasted-track scene. The **Train control** panel in the upper-right corner of
the running scene also switches between UDP and keyboard input. UDP remains the
default. The dispatch plan carries `input_source` (`udp` or `keyboard`). Keyboard
operation has a fixed 160 km/h limit, independent of the dispatch speed setting.
On first entering keyboard mode without a fresh UDP state, speed starts at
154 km/h; live UDP takeover retains the current speed, capped at 160 km/h.

- Hold **W** to apply traction and move forward.
- Hold **S** to brake to a standstill. Braking takes priority if both are held.
- Release both to coast; the train slowly loses speed.
- **C / 6** toggles cab view; **V** toggles the speed curve.
- W/S camera movement is disabled in keyboard mode.

Keyboard control uses a simple preview model: traction 15 m/s2, braking
0.8 m/s2, coasting resistance 0.015 m/s2. It stops at the 8 km route endpoint
and does not reverse. It is not the external LTD/31DOF dynamics simulation.
The controller parameters are in `keyboard_train_driver.gd`.

Switching to keyboard retains displayed mileage and fresh UDP speed (packets
older than one second start at zero speed). UDP body/bogie/wheelset offsets
are reset and incoming UDP packets are discarded while keyboard control is
active. Switching back holds position and stops wheel animation until a new
UDP state arrives; the external solver then determines mileage and speed.
A newly restarted solver may begin again at sequence zero.

Direct launch from the project directory (PowerShell):

```powershell
& 'C:\GodotEngine\Godot_v4.4.1-stable_win64.exe\Godot_v4.4.1-stable_win64_console.exe' --rendering-method gl_compatibility --path . res://scenes/ballasted_track/scene.tscn -- --input-source=keyboard
```

Headless regression test (acceleration/braking, limits, dispatch selection,
actual consist movement/wheel speeds, speed chart, UDP isolation and restart):

```powershell
& 'C:\GodotEngine\Godot_v4.4.1-stable_win64.exe\Godot_v4.4.1-stable_win64_console.exe' --headless --path . --script res://scenes/ballasted_track/test_keyboard_control.gd -- --stream-smoke-test --dispatch=ballasted_track
```

To check the complete rendered scene, replace `--headless` with
`--rendering-method gl_compatibility`, remove `--stream-smoke-test`, and append
`--capture-control-test`. This saves `.godot/keyboard-control-test.png`.
