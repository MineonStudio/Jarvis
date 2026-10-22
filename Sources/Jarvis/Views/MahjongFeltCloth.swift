import AppKit
import SceneKit

/// World-space materials keep their grain and scale as the window changes size.
@MainActor
enum MahjongFeltCloth {
    static func material(style: MahjongTableStyle = .brocade) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.locksAmbientWithDiffuse = true
        material.diffuse.contents = style.color
        material.specular.contents = NSColor(white: style == .walnut || style == .leather ? 0.24 : 0.16, alpha: 1)
        material.shininess = style == .walnut ? 0.22 : 0.08
        material.shaderModifiers = [.surface: surfaceShader
            .replacingOccurrences(of: "__RED__", with: String(style.dye.red))
            .replacingOccurrences(of: "__GREEN__", with: String(style.dye.green))
            .replacingOccurrences(of: "__BLUE__", with: String(style.dye.blue))
            .replacingOccurrences(of: "__STYLE__", with: String(style.textureID))]
        return material
    }

    /// Each finish has its own structure, rather than a tint on one fabric.
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
    float clump = feltFbm4(u * 9.5 + 2.0, v * 8.5);
    float grain = feltFbm3(u * 48.0, v * 46.0);
    float nap = feltFbm3(u * 36.0, v * 14.0);
    float grainShift = grain - 0.5;
    float napShift = nap - 0.5;
    float3 dye = float3(__RED__, __GREEN__, __BLUE__);
    float3 color = dye;
    float relief = 0.42;
    if (__STYLE__ == 1) {
        float warp = sin(world.x * 68.0) * sin(world.z * 68.0);
        color += warp * 0.012 + grainShift * 0.025 + (clump - 0.5) * 0.024;
        color += sin(world.x * 34.0) * 0.006;
        relief = 0.25;
    } else if (__STYLE__ == 2) {
        float bend = feltFbm3(world.x * 0.28, world.z * 0.12);
        float growth = sin(world.x * 14.0 + bend * 17.0 + sin(world.z * 0.7) * 0.7);
        float rings = pow(0.5 + 0.5 * growth, 9.0);
        float fine = feltFbm3(world.x * 26.0 + bend * 3.0, world.z * 0.25);
        color -= rings * float3(0.035, 0.023, 0.012);
        color += (fine - 0.5) * float3(0.06, 0.035, 0.018);
        color += (clump - 0.5) * float3(0.05, 0.035, 0.02) + grainShift * 0.008;
        relief = 0.06;
    } else if (__STYLE__ == 3) {
        float pebble = feltNoise(world.x * 65.0, world.z * 65.0);
        color += (pebble - 0.5) * 0.019 + (clump - 0.5) * 0.026;
        color += napShift * float3(0.02, 0.008, 0.01);
        relief = 0.18;
    } else {
        float2 diamonds = abs(fract(float2(world.x + world.z, world.x - world.z) * 0.24) - 0.5);
        float seam = min(abs(diamonds.x - 0.44), abs(diamonds.y - 0.44));
        float threads = 1.0 - smoothstep(0.004, 0.014, seam);
        float inner = 1.0 - smoothstep(0.003, 0.009, min(abs(diamonds.x - 0.405), abs(diamonds.y - 0.405)));
        color += (threads + inner * 0.4) * float3(0.045, 0.033, 0.014);
        color += grainShift * 0.018 + sin(world.x * 62.0) * sin(world.z * 62.0) * 0.004;
        relief = 0.12;
    }
    _surface.diffuse.rgb = pow(saturate(color), float3(2.2));
    float e = 0.008;
    float hx = feltHeight(world.x - e, world.z) - feltHeight(world.x + e, world.z);
    float hz = feltHeight(world.x, world.z - e) - feltHeight(world.x, world.z + e);
    float3 nWorld = normalize(float3(hx * 2.4, 1.0, hz * 2.4));
    float3 nView = normalize((scn_frame.viewTransform * float4(nWorld, 0.0)).xyz);
    _surface.normal = normalize(mix(_surface.normal, nView, relief));
    """
}
