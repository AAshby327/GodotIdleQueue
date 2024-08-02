# GodotIdleQueue
A godot optimization script that allows processes to run between frames on the main thread.

Many games require complex functions that if called all at once will cause the frame rate to jitter. Usually, this is solved using mutlithreading, but multithreaded processes in the Godot Engine are very limited in their capabilities. The IdleQueue plugin allows method calls to be queued and run between frames preserving the game's frame rate. The queuing process works similar to the call_deferred method, where the engine waits until the end of the frame to call the queued methods. This script, unlike call_deferred, will not call all queued calls all at once, lowering the frame rate, but instead calling as many as it can between frames to keep a consistent frame rate. 

This script is perfect for features such as procedural generation and loading large scenes. 
