#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;    // Index 0, 1
uniform float uAlpha;        // Index 2
uniform float uBeta;         // Index 3
uniform float uZoom;         // Index 4
uniform vec2 uMoilSize;      // Index 5, 6
uniform vec2 uMoilCenter;    // Index 7, 8
uniform float uCpRatio;      // Index 9
uniform float p0;            // Index 10
uniform float p1;            // Index 11
uniform float p2;            // Index 12
uniform float p3;            // Index 13
uniform float p4;            // Index 14
uniform float p5;            // Index 15
uniform sampler2D uTexture;  // Sampler 0

out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    float positionX = fragCoord.x;
    float positionY = fragCoord.y;

    float dcx = uResolution.x / 2.0;
    float dcy = uResolution.y / 2.0;

    float mAlphaOffset = uAlpha * (3.1415926 / 180.0);
    float mBetaOffset = (uBeta + 180.0) * (3.1415926 / 180.0);

    float widthCosB = 1.27 * cos(mBetaOffset);
    float heightCosASinB = 1.27 * cos(mAlphaOffset) * sin(mBetaOffset);
    float flZoomSinASinB = 250.0 * uZoom * sin(mAlphaOffset) * sin(mBetaOffset);
    float widthSinB = 1.27 * sin(mBetaOffset);
    float heightCosACosB = 1.27 * cos(mAlphaOffset) * cos(mBetaOffset);
    float flZoomSinACosB = 250.0 * uZoom * sin(mAlphaOffset) * cos(mBetaOffset);
    float heightSinA = 1.27 * sin(mAlphaOffset);
    float flZoomCosA = 250.0 * uZoom * cos(mAlphaOffset);

    float tempX = (positionX - dcx) * widthCosB - (positionY - dcy) * heightCosASinB + flZoomSinASinB;
    float tempY = (positionX - dcx) * widthSinB + (positionY - dcy) * heightCosACosB - flZoomSinACosB;
    float tempZ = (positionY - dcy) * heightSinA + flZoomCosA;

    float alpha = atan(sqrt(tempX * tempX + tempY * tempY), tempZ);
    float beta = 0.0;

    if (tempX != 0.0) {
        beta = atan(tempY, tempX);
    } else if (tempY >= 0.0) {
        beta = 3.1415926 / 2.0;
    } else {
        beta = -(3.1415926 / 2.0);
    }

    float alpha2 = alpha * alpha;
    float alpha3 = alpha2 * alpha;
    float alpha4 = alpha3 * alpha;
    float alpha5 = alpha4 * alpha;
    float alpha6 = alpha5 * alpha;

    float rho = (p0 * alpha6 + p1 * alpha5 + p2 * alpha4 + p3 * alpha3 + p4 * alpha2 + p5 * alpha) * uCpRatio;

    float origPostionX = uMoilCenter.x - rho * cos(beta);
    float origPostionY = uMoilCenter.y - rho * sin(beta);

    vec2 texCoord = vec2(origPostionX, origPostionY) / uMoilSize;

    if (texCoord.x < 0.0 || texCoord.x > 1.0 || texCoord.y < 0.0 || texCoord.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        fragColor = texture(uTexture, texCoord);
    }
}