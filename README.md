# Mini-Golf
Repository for a mini golf game based on the NEXYS A7-100T FPGA. 


## Project Behavior
### Hardware Needed
1. NEXYS A7-100T FPGA\
Board\
![Board](SourceFolder/board.jpg)
Board Box\
![BoardBox](SourceFolder/boardbox.jpg)
3. A device that can run Vivado
4. Micro-USB to USB cable
5. External display
6. VGA, USB, and AUX to HDMI adapter\
Adapter\
![Adapter](SourceFolder/adapter.jpg)

## Steps to Run
1. With a new project in Vivado, add all of the supplementary files given in this repository as sources
2. Connect a NEXYS A7-100T FPGA to your device
3. Connect the NEXYS board to an external display using the VGA to HDMI adpater
4. Click "Run Synthesis"
5. Click "Run Implementation"
6. Click "Generate Bistream"
7. Once this process is complete, click "Program Device", let the system auto-connect, and the game should appear on your display

## Summary

## Modifications
We originally took code from the "Pong" lab from our Digital System Design class.
It features a simple ball and bar where the ball bounces endlessly around the screen.
Should the ball hit the bar, it will bounce off of it in the opposite direction.
We took these physics as a base for our "golf ball" and added a lot onto it.

## Project in Action
Video recording: https://youtu.be/8sf0UF7UczM

## Conclusion
