#ifndef CAMERA_DRIVER_H
#define CAMERA_DRIVER_H

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

// Camera control functions
void open_camera();
void stop_camera();
void pause_camera();
void resume_camera();
void init_camera(int width, int height);
void close_camera();

// Frame capture functions
uint8_t* next_frame();
int frame_size();
uint8_t is_camera_open();
uint8_t is_camera_paused();

#ifdef __cplusplus
}
#endif

#endif // CAMERA_DRIVER_H