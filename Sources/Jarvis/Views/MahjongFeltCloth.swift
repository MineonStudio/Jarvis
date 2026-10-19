import AppKit
import SceneKit

/// One wool cloth in world space. The pattern follows the table, so a wider window
/// shows more of the same baize instead of a second flat color behind a fixed canvas.
@MainActor
enum MahjongFeltCloth {
    static func material() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.locksAmbientWithDiffuse = true
        material.diffuse.contents = NSColor(red: 0.055, green: 0.29, blue: 0.155, alpha: 1)
        material.specular.contents = NSColor(white: 0.16, alpha: 1)
        material.shininess = 0.08
        material.shaderModifiers = [.surface: surfaceShader]
        return material
    }

    /// Same dye, fiber, and nap as the old 12.2 map, sampled from world XZ.
    private static let surfaceShader = """
    float feltHash(int x, int y) {
        uint n = uint(x) * 374761393u + uint(y) * 668265263u;
        n = (n ^ (n >> 13u)) * 1274126177u;
        return float(n & 0x00FFFFFFu) / float(0x00FFFFFFu);
    }

    float feltNoise(float x, float y) {
        float x0f = floor(x);
        float y0f = floor(y);
        int x0 = int(x0f);
        int y0 = int(y0f);
        float fx = x - x0f;
        float fy = y - y0f;
        float ux = fx * fx * (3.0 - 2.0 * fx);
        float uy = fy * fy * (3.0 - 2.0 * fy);
        float a = feltHash(x0, y0);
        float b = feltHash(x0 + 1, y0);
        float c = feltHash(x0, y0 + 1);
        float d = feltHash(x0 + 1, y0 + 1);
        return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
    }

    float feltFbm3(float x, float y) {
        float value = 0.0;
        float amplitude = 0.5;
        float frequency = 1.0;
        float total = 0.0;
        for (int i = 0; i < 3; i++) {
            value += amplitude * feltNoise(x * frequency, y * frequency);
            total += amplitude;
            amplitude *= 0.5;
            frequency *= 2.0;
        }
        return value / total;
    }

    float feltFbm4(float x, float y) {
        float value = 0.0;
        float amplitude = 0.5;
        float frequency = 1.0;
        float total = 0.0;
        for (int i = 0; i < 4; i++) {
            value += amplitude * feltNoise(x * frequency, y * frequency);
            total += amplitude;
            amplitude *= 0.5;
            frequency *= 2.0;
        }
        return value / total;
    }

    float feltHeight(float x, float z) {
        float u = x / 12.2;
        float v = z / 12.2;
        float grain = feltFbm3(u * 48.0, v * 46.0);
        float nap = feltFbm3(u * 36.0, v * 14.0);
        return 0.55 + (grain - 0.5) * 0.9 + (nap - 0.5) * 1.4;
    }

    #pragma body
    float3 world = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float u = world.x / 12.2;
    float v = world.z / 12.2;
    float blot = feltFbm3(u * 2.6 + 0.4, v * 2.4);
    float clump = feltFbm4(u * 9.5 + 2.0, v * 8.5);
    float grain = feltFbm3(u * 48.0, v * 46.0);
    float nap = feltFbm3(u * 36.0, v * 14.0);
    float grainShift = grain - 0.5;
    float napShift = nap - 0.5;
    float red = 0.055 + (blot - 0.5) * 0.035 + (clump - 0.5) * 0.02;
    float green = 0.29 + (blot - 0.5) * 0.07 + (clump - 0.5) * 0.04;
    float blue = 0.155 + (blot - 0.5) * 0.03 + (clump - 0.5) * 0.015;
    red += grainShift * 0.03 + napShift * 0.012;
    green += grainShift * 0.055 + napShift * 0.02;
    blue += grainShift * 0.02 + napShift * 0.006;
    red += max(napShift, 0.0) * 0.02;
    // The old cloth stored these values in an sRGB texture. Diffuse here is linear.
    _surface.diffuse.rgb = pow(saturate(float3(red, green, blue)), float3(2.2));
    float e = 0.008;
    float hx = feltHeight(world.x - e, world.z) - feltHeight(world.x + e, world.z);
    float hz = feltHeight(world.x, world.z - e) - feltHeight(world.x, world.z + e);
    float3 nWorld = normalize(float3(hx * 2.4, 1.0, hz * 2.4));
    float3 nView = normalize((scn_frame.viewTransform * float4(nWorld, 0.0)).xyz);
    _surface.normal = normalize(mix(_surface.normal, nView, 0.42));
    """
}
