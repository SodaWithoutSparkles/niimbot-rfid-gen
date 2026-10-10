/**
 * OpenRoll — NIIMBOT NFC tag generator (TypeScript port)
 *
 * Ported from the minified bundle `index-C3TVx2kG.js`.
 * Only the domain/pure logic is ported; the Svelte runtime + DOM
 * rendering glue is intentionally excluded.
 *
 * Pipeline (matches the original exactly):
 *   template -> set media params (Ri) -> apply catalogue barcode (co)
 *            -> build ORF1 provisioning dump (Ua) -> validate (Wa)
 *            -> export to raw / chameleon / proxmark / flipper (ro)
 */

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const TEA_KEY = [52385, 29367, 26456, 26057] as const;
const TEA_DELTA = 2654435769; // 0x9E3779B9

export const MAX_READ_SIZE = 32768; // qa
export const MAX_NOMINAL_QUANTITY = 54612; // ua

const ORF1_MAGIC = Uint8Array.of(0x4f, 0x52, 0x46, 0x31); // "ORF1"  (Ra)
const PWD_BYTES = Uint8Array.of(0x12, 0x34, 0x56, 0x78); //          (za)
const PACK_BYTES = Uint8Array.of(0x55, 0x55); // "UU"                (Ba)

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/** Mirrors the minified `Pi` class (an Error carrying a form field name). */
export class FieldError extends Error {
    readonly field: string;
    constructor(field: string, message: string) {
        super(message);
        this.name = 'FieldError';
        this.field = field;
    }
}

// ---------------------------------------------------------------------------
// Byte / hex helpers  (yi, bi, xi, Si, Ci, Ya)
// ---------------------------------------------------------------------------

export function hexToBytes(hex: string): Uint8Array {
    if (!/^(?:[0-9a-fA-F]{2})*$/.test(hex)) {
        throw new Error('Invalid hexadecimal bytes.');
    }
    return Uint8Array.from(hex.match(/../g) ?? [], (b) => parseInt(b, 16));
}

export function bytesToHex(bytes: Uint8Array): string {
    return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
    return a.length === b.length && a.every((byte, i) => byte === b[i]);
}

function dataView(bytes: Uint8Array): DataView {
    return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
}

/** Parses a 7-byte UID from raw hex or `:`/`-`/whitespace separated pairs. */
export function parseUid(input: string): Uint8Array {
    const trimmed = input.trim();
    if (/^[0-9a-fA-F]{14}$/.test(trimmed)) return hexToBytes(trimmed);
    for (const sep of [':', '-', '\\s+']) {
        if (new RegExp(`^[0-9a-fA-F]{2}(?:${sep}[0-9a-fA-F]{2}){6}$`).test(trimmed)) {
            return hexToBytes(trimmed.replace(new RegExp(sep, 'g'), ''));
        }
    }
    throw new Error(
        'Enter 14 hexadecimal characters, or seven byte pairs separated by spaces, colons or hyphens.',
    );
}

/** "1D E1 A1 …" style display (Ya). */
export function formatUidBytes(bytes: Uint8Array): string {
    return bytesToHex(bytes).toUpperCase().match(/../g)?.join(' ') ?? '';
}

// ---------------------------------------------------------------------------
// TEA cipher  (Ei)
// ---------------------------------------------------------------------------

/**
 * Tiny Encryption Algorithm over 8-byte blocks.
 * `decrypt=false` encrypts, `decrypt=true` decrypts. Little-endian words.
 */
export function teaCrypt(input: Uint8Array, decrypt = false): Uint8Array {
    if (input.length % 8) throw new Error('TEA requires complete eight-byte blocks.');
    const out = input.slice();
    const view = dataView(out);

    for (let off = 0; off < input.length; off += 8) {
        let v0 = view.getUint32(off, true);
        let v1 = view.getUint32(off + 4, true);
        let sum = decrypt ? (TEA_DELTA * 32) >>> 0 : 0;

        for (let i = 0; i < 32; i++) {
            if (decrypt) {
                v1 = (v1 - ((((v0 << 4) + TEA_KEY[2]) ^ (v0 + sum)) ^ ((v0 >>> 5) + TEA_KEY[3]))) >>> 0;
                v0 = (v0 - ((((v1 << 4) + TEA_KEY[0]) ^ (v1 + sum)) ^ ((v1 >>> 5) + TEA_KEY[1]))) >>> 0;
                sum = (sum - TEA_DELTA) >>> 0;
            } else {
                sum = (sum + TEA_DELTA) >>> 0;
                v0 = (v0 + ((((v1 << 4) + TEA_KEY[0]) ^ (v1 + sum)) ^ ((v1 >>> 5) + TEA_KEY[1]))) >>> 0;
                v1 = (v1 + ((((v0 << 4) + TEA_KEY[2]) ^ (v0 + sum)) ^ ((v0 >>> 5) + TEA_KEY[3]))) >>> 0;
            }
        }

        view.setUint32(off, v0, true);
        view.setUint32(off + 4, v1, true);
    }
    return out;
}

// ---------------------------------------------------------------------------
// CRC32  (Di)
// ---------------------------------------------------------------------------

export function crc32(bytes: Uint8Array): number {
    let crc = 0xffffffff;
    for (const byte of bytes) {
        crc ^= byte;
        for (let i = 0; i < 8; i++) {
            crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
        }
    }
    return (crc ^ 0xffffffff) >>> 0;
}

// ---------------------------------------------------------------------------
// NIIMBOT 120-byte payload  (Oi, ki, Ai, ji)
// ---------------------------------------------------------------------------

export interface NiimbotPayload {
    mutable: Uint8Array; // 4 bytes
    fixed: Uint8Array; // 108 bytes
    count: number;
    capacity: number;
}

export function decodePayload(bytes: Uint8Array): NiimbotPayload {
    if (bytes.length !== 120) throw new Error('NIIMBOT payload must contain 120 bytes.');
    const plain = teaCrypt(bytes, true);
    const mutable = plain.slice(0, 4);
    const fixed = plain.slice(8, 116);
    const view = dataView(plain);
    if (crc32(mutable) !== view.getUint32(4, true)) throw new Error('Mutable CRC failed.');
    if (crc32(fixed) !== view.getUint32(116, true)) throw new Error('Fixed CRC failed.');
    return {
        mutable,
        fixed,
        count: dataView(mutable).getUint16(2, true),
        capacity: dataView(fixed).getUint16(58, true),
    };
}

export function encodePayload(mutable: Uint8Array, fixed: Uint8Array): Uint8Array {
    if (mutable.length !== 4 || fixed.length !== 108) throw new Error('Invalid plaintext lengths.');
    const plain = new Uint8Array(120);
    plain.set(mutable, 0);
    plain.set(fixed, 8);
    const view = dataView(plain);
    view.setUint32(4, crc32(mutable), true);
    view.setUint32(116, crc32(fixed), true);
    return teaCrypt(plain, false);
}

/** Rebuilds the payload for a new UID and resets the usage counter to 0. */
export function rebindUid(payload: Uint8Array, uid: Uint8Array): Uint8Array {
    if (uid.length !== 7) throw new Error('Target UID must contain exactly seven bytes.');
    const { mutable, fixed } = decodePayload(payload);
    fixed.set([0x88, ...uid], 0);
    dataView(mutable).setUint16(2, 0, true);
    return encodePayload(mutable, fixed);
}

export function assertFixedIdentity(fixed: Uint8Array, uid: Uint8Array): void {
    if (!bytesEqual(fixed.slice(0, 8), Uint8Array.of(0x88, ...uid))) {
        throw new Error('Fixed identity does not match target UID.');
    }
}

// ---------------------------------------------------------------------------
// Media parameters  (Mi, Ni, Pi, Fi, Ii, Li, Ri, da)
// ---------------------------------------------------------------------------

export interface MediaParameters {
    mediaType: number;
    widthMm: number;
    heightMm: number;
    gapMm: number;
    nominalQuantity: number;
    usageLimit: number;
}

export type ParameterKey = keyof Omit<MediaParameters, 'mediaType'>;

export interface MediaTypeOption {
    value: number;
    label: string;
}

export const MEDIA_TYPES: MediaTypeOption[] = [
    { value: 1, label: 'Gap labels' },
    { value: 2, label: 'Black-mark labels' },
    { value: 3, label: 'Continuous media' },
    { value: 4, label: 'Hole-indexed labels' },
    { value: 5, label: 'Transparent labels' },
    { value: 10, label: 'Black-mark + gap labels' },
];

export interface ParameterField {
    key: ParameterKey;
    label: string;
    offset: number;
    size: 1 | 2;
    min: number;
    max: number;
}

export const PARAMETER_FIELDS: ParameterField[] = [
    { key: 'widthMm', label: 'Width (mm)', offset: 82, size: 1, min: 1, max: 255 },
    { key: 'heightMm', label: 'Length (mm)', offset: 83, size: 1, min: 1, max: 255 },
    { key: 'gapMm', label: 'Gap (mm)', offset: 87, size: 1, min: 0, max: 255 },
    { key: 'nominalQuantity', label: 'Nominal quantity', offset: 84, size: 2, min: 1, max: 65535 },
    { key: 'usageLimit', label: 'Usage limit', offset: 58, size: 2, min: 1, max: 65535 },
];

export function validateParameters(params: MediaParameters): void {
    if (!MEDIA_TYPES.some((m) => m.value === params.mediaType)) {
        throw new FieldError('mediaType', 'Select a listed media type.');
    }
    for (const field of PARAMETER_FIELDS) {
        const value = params[field.key];
        const min = field.key === 'heightMm' && params.mediaType === 3 ? 0 : field.min;
        if (field.key === 'gapMm' && Number.isFinite(value) && !Number.isInteger(value)) {
            throw new FieldError(
                'gapMm',
                `The known NIIMBOT gap encoding supports whole millimetres only. ${value} mm cannot be encoded exactly; OpenRoll will not round it automatically.`,
            );
        }
        if (!Number.isInteger(value) || value < min || value > field.max) {
            throw new FieldError(field.key, `${field.label} must be a whole number from ${min} to ${field.max}.`);
        }
    }
}

/** usageLimit = round(nominalQuantity × 1.2)  (da) */
export function computeUsageLimit(nominalQuantity: number): number {
    if (!Number.isInteger(nominalQuantity) || nominalQuantity < 1 || nominalQuantity > MAX_NOMINAL_QUANTITY) {
        throw new FieldError(
            'nominalQuantity',
            `Nominal quantity must be a whole number from 1 to ${MAX_NOMINAL_QUANTITY} so its 1.2× usage limit fits the tag.`,
        );
    }
    return Math.round((nominalQuantity * 6) / 5);
}

/** Rejects payloads using extended/fractional dimension bytes (Ii). */
function decodeEditablePayload(payload: Uint8Array): NiimbotPayload {
    const decoded = decodePayload(payload);
    if ([98, 99, 102].some((off) => decoded.fixed[off] !== 0)) {
        throw new Error('Extended or fractional dimensions are not supported by this editor.');
    }
    return decoded;
}

export function payloadToParameters(payload: Uint8Array): MediaParameters {
    const { fixed } = decodeEditablePayload(payload);
    const view = dataView(fixed);
    const result: Record<string, number> = { mediaType: fixed[60] };
    for (const field of PARAMETER_FIELDS) {
        result[field.key] = field.size === 1 ? fixed[field.offset] : view.getUint16(field.offset, true);
    }
    const params = result as unknown as MediaParameters;
    validateParameters(params);
    return params;
}

export function parametersToPayload(payload: Uint8Array, params: MediaParameters): Uint8Array {
    validateParameters(params);
    const { mutable, fixed } = decodeEditablePayload(payload);
    fixed[60] = params.mediaType;
    const view = dataView(fixed);
    for (const field of PARAMETER_FIELDS) {
        const value = params[field.key];
        if (field.size === 1) fixed[field.offset] = value;
        else view.setUint16(field.offset, value, true);
    }
    return encodePayload(mutable, fixed);
}

// ---------------------------------------------------------------------------
// Profile / template data  (vi, zi, Vi, Hi, Ui)
// ---------------------------------------------------------------------------

export const PRINTER_PROFILE = {
    id: 'niimbot-b1-fw-6-19',
    name: 'NIIMBOT B1',
    compatibility: 'Tested on firmware 6.19',
} as const;

export const BRAND = { id: 'niimbot', name: 'NIIMBOT' } as const;

export const ROLL_PROFILE = {
    schema_version: 1,
    id: 'niimbot-30307-50x30',
    revision: 1,
    printer_profiles: ['niimbot-b1-fw-6-19'],
    display_name: '30307 freezer labels, 50 x 30 mm, 230 labels',
    physical: { width_mm: 50, height_mm: 30, gap_mm: 6, nominal_quantity: 230 },
    capacity_limit: 276,
    template: {
        format: 'niimbot-pages5-34-raw-v1',
        hex:
            '742fc763e017dbf98ed6902b0c984b48f5de9eff112aac55452558e8848403e8' +
            'eabebae8bb22ebc9cc3bb5bf9addc656aa7fe67ccd0adce494803b743a8b6488' +
            '741abe5d162ff80ed7e61e8f66e35d5d3e24e38a6a56550e6d152f2a21a4ebe3' +
            'db4b279be1d8d6832b4f1f29d68fba0b2f371ab05aad3d1e',
        sha256: 'bfb84efd42f1fd89d99d165e1fbcaba7d3bb2e661e264701a505fff100b2e049',
    },
} as const;

/** Default decoded parameters from the template (Hi). */
export const DEFAULT_PARAMETERS: Readonly<MediaParameters> = Object.freeze(
    payloadToParameters(hexToBytes(ROLL_PROFILE.template.hex)),
);

export async function loadTemplate(printerProfileId: string, rollProfileId: string): Promise<Uint8Array> {
    if (
        printerProfileId !== PRINTER_PROFILE.id ||
        rollProfileId !== ROLL_PROFILE.id ||
        !(ROLL_PROFILE.printer_profiles as readonly string[]).includes(printerProfileId)
    ) {
        throw new Error('This printer and roll combination is not supported.');
    }
    if (
        ROLL_PROFILE.schema_version !== 1 ||
        ROLL_PROFILE.revision !== 1 ||
        ROLL_PROFILE.template.format !== 'niimbot-pages5-34-raw-v1'
    ) {
        throw new Error('Unsupported profile version.');
    }
    const template = hexToBytes(ROLL_PROFILE.template.hex);
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', Uint8Array.from(template)));
    if (bytesToHex(digest) !== ROLL_PROFILE.template.sha256) {
        throw new Error('Profile template integrity check failed.');
    }
    if (decodePayload(template).capacity !== ROLL_PROFILE.capacity_limit) {
        throw new Error('Profile capacity mismatch.');
    }
    return template;
}

export function isCustomParameters(params: MediaParameters): boolean {
    return (Object.entries(DEFAULT_PARAMETERS) as [keyof MediaParameters, number][]).some(
        ([key, value]) => params[key] !== value,
    );
}

// ---------------------------------------------------------------------------
// UID / BCC + provisioning masks  (Ha, Va)
// ---------------------------------------------------------------------------

/** UID0..2, BCC0, UID3..6, BCC1 — nine header bytes. */
export function uidHeader(uid: Uint8Array): Uint8Array {
    if (uid.length !== 7) throw new Error('Target UID must contain exactly seven bytes.');
    return Uint8Array.of(
        uid[0],
        uid[1],
        uid[2],
        0x88 ^ uid[0] ^ uid[1] ^ uid[2],
        uid[3],
        uid[4],
        uid[5],
        uid[6],
        uid[3] ^ uid[4] ^ uid[5] ^ uid[6],
    );
}

export interface ProvisioningMasks {
    known: Uint8Array;
    write: Uint8Array;
}

export function provisioningMasks(): ProvisioningMasks {
    const known = new Uint8Array(180);
    const write = new Uint8Array(180);
    known.fill(0xff, 0, 9);
    for (const [start, end] of [
        [20, 140],
        [172, 178],
    ]) {
        known.fill(0xff, start, end);
        write.fill(0xff, start, end);
    }
    for (const [offset, value] of [
        [164, 192],
        [167, 255],
        [168, 159],
    ]) {
        known[offset] = value;
        write[offset] = value;
    }
    return { known, write };
}

// ---------------------------------------------------------------------------
// ORF1 provisioning dump  (Ua, Wa)
// ---------------------------------------------------------------------------

export interface Orf1Info {
    format: 'ORF1';
    bytes: 544;
    pageCount: 45;
    uid: string;
    fixedCrcValid: boolean;
    mutableCrcValid: boolean;
    profileMatches: boolean;
    count: number;
    capacity: number;
    permanentLockWrites: boolean;
}

/** Builds the 544-byte ORF1 provisioning image. */
export function buildOrf1(payload: Uint8Array, uid: Uint8Array): Uint8Array {
    const memory = new Uint8Array(180);
    memory.set(uidHeader(uid), 0);
    memory.set(rebindUid(payload, uid), 20);
    memory[167] = 0xff;
    memory.set(PWD_BYTES, 172);
    memory.set(PACK_BYTES, 176);

    const { known, write } = provisioningMasks();
    const out = new Uint8Array(544);
    out.set(ORF1_MAGIC, 0);
    out.set(memory, 4);
    out.set(known, 184);
    out.set(write, 364);
    return out;
}

export function validateOrf1(orf1: Uint8Array, payload: Uint8Array, uid: Uint8Array): Orf1Info {
    if (orf1.length !== 544 || !bytesEqual(orf1.slice(0, 4), ORF1_MAGIC)) {
        throw new Error('Expected a 544-byte ORF1 provisioning dump.');
    }
    const memory = orf1.slice(4, 184);
    const known = orf1.slice(184, 364);
    const write = orf1.slice(364);
    const masks = provisioningMasks();

    if (!bytesEqual(known, masks.known) || !bytesEqual(write, masks.write)) {
        throw new Error('Invalid masks: manufacturer and lock writes are forbidden.');
    }
    if (memory.some((byte, i) => (byte & ~known[i]) !== 0)) {
        throw new Error('Unknown bits must remain canonical preserve placeholders.');
    }
    if (!bytesEqual(memory.slice(0, 9), uidHeader(uid))) {
        throw new Error('Target UID/BCC mismatch.');
    }
    if (
        memory[164] !== 0 ||
        memory[167] !== 0xff ||
        memory[168] !== 0 ||
        !bytesEqual(memory.slice(172, 176), PWD_BYTES) ||
        !bytesEqual(memory.slice(176, 178), PACK_BYTES)
    ) {
        throw new Error('Authentication/configuration policy mismatch.');
    }

    const decoded = decodePayload(memory.slice(20, 140));
    assertFixedIdentity(decoded.fixed, uid);
    if (decoded.count !== 0) throw new Error('Fresh-roll count must be zero.');
    if (!bytesEqual(orf1, buildOrf1(payload, uid))) {
        throw new Error('Dump does not match the selected profile.');
    }

    return {
        format: 'ORF1',
        bytes: 544,
        pageCount: 45,
        uid: bytesToHex(uid),
        fixedCrcValid: true,
        mutableCrcValid: true,
        profileMatches: true,
        count: decoded.count,
        capacity: decoded.capacity,
        permanentLockWrites: false,
    };
}

// ---------------------------------------------------------------------------
// Tag types  (Fa, Ia, La)
// ---------------------------------------------------------------------------

export type TagTypeId = 'NTAG213' | 'NTAG215' | 'NTAG216';

export interface TagTypeSpec {
    id: TagTypeId;
    label: string;
    pages: number;
    configPage: number;
    passwordPage: number;
    packPage: number;
    ccSize: number;
    versionSize: number;
    chameleonId: number;
    evidence: string;
}

export const TAG_TYPES: TagTypeSpec[] = [
    {
        id: 'NTAG213',
        label: 'NTAG213',
        pages: 45,
        configPage: 41,
        passwordPage: 43,
        packPage: 44,
        ccSize: 18,
        versionSize: 15,
        chameleonId: 1100,
        evidence: 'Tested with B1 firmware 6.19.',
    },
    {
        id: 'NTAG215',
        label: 'NTAG215 · experimental',
        pages: 135,
        configPage: 131,
        passwordPage: 133,
        packPage: 134,
        ccSize: 62,
        versionSize: 17,
        chameleonId: 1101,
        evidence: 'Experimental: generated files are validated; printer compatibility has not been physically tested.',
    },
    {
        id: 'NTAG216',
        label: 'NTAG216',
        pages: 231,
        configPage: 227,
        passwordPage: 229,
        packPage: 230,
        ccSize: 109,
        versionSize: 19,
        chameleonId: 1102,
        evidence: 'Contributor reports printing on B1 Pro firmware 2.12; readback supports counter writeback.',
    },
];

export function getTagType(id: string): TagTypeSpec {
    const spec = TAG_TYPES.find((t) => t.id === id);
    if (!spec) throw new Error('Unsupported tag type.');
    return spec;
}

export function tagTypeFromByteLength(length: number): TagTypeId {
    const spec = TAG_TYPES.find((t) => t.pages * 4 === length);
    if (!spec) {
        throw new Error(
            'Target read must contain exactly 180 bytes (NTAG213), 540 bytes (NTAG215) or 924 bytes (NTAG216).',
        );
    }
    return spec.id;
}

// ---------------------------------------------------------------------------
// Blank tag preset + BCC helpers  (Ja, Qa, $a)
// ---------------------------------------------------------------------------

export function blankTagPreset(uid: Uint8Array, tagType: TagTypeId): Uint8Array {
    const spec = getTagType(tagType);
    if (uid.length !== 7) throw new Error('Target UID must contain exactly seven bytes.');
    const memory = new Uint8Array(spec.pages * 4);
    memory.set(uid.slice(0, 3), 0);
    memory[3] = 0x88 ^ uid[0] ^ uid[1] ^ uid[2];
    memory.set(uid.slice(3), 4);
    memory[8] = uid[3] ^ uid[4] ^ uid[5] ^ uid[6];
    memory[9] = 0xc0;
    memory.set(hexToBytes('e11012000103a00c340300fe'), 12);
    memory[14] = spec.ccSize;
    if (tagType !== 'NTAG213') memory.set(hexToBytes('0300fe00'), 16);
    memory[spec.configPage * 4 - 1] = 0xbd;
    memory[spec.configPage * 4] = tagType === 'NTAG213' ? 0 : 4;
    memory[spec.configPage * 4 + 3] = 0xff;
    return memory;
}

export function assertMemoryBcc(memory: Uint8Array): Uint8Array {
    tagTypeFromByteLength(memory.length);
    if (
        memory[3] !== (0x88 ^ memory[0] ^ memory[1] ^ memory[2]) ||
        memory[8] !== (memory[4] ^ memory[5] ^ memory[6] ^ memory[7])
    ) {
        throw new Error('Target read has invalid UID check bytes. Use an unmodified read of the target tag.');
    }
    return memory.slice();
}

export function extractUid(dump: { memory: Uint8Array }): Uint8Array {
    const memory = assertMemoryBcc(dump.memory);
    return Uint8Array.of(...memory.slice(0, 3), ...memory.slice(4, 8));
}

// ---------------------------------------------------------------------------
// Barcode / catalogue  (ao, oo, so, co, lo)
// ---------------------------------------------------------------------------

export interface CatalogueEntry {
    mediaType: number;
    widthMm: number;
    heightMm: number;
    barcode: string;
    sourceId: string;
    barcodeEvidence: string;
}

export const CATALOGUE_SHA256 = 'dd1c930f3ac0808fa3e0498fa26986ceee807980a06bffe86c987b29efc56efb';

export const CATALOGUE: CatalogueEntry[] = [
    { mediaType: 1, widthMm: 8, heightMm: 25, barcode: '6977031213614', sourceId: '80006700', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 10, heightMm: 25, barcode: '08042110', sourceId: '80032461', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 12, heightMm: 22, barcode: '010424774', sourceId: '80028832', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 12, heightMm: 24, barcode: '08132280', sourceId: '80002444', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 12, heightMm: 30, barcode: '6972842747594', sourceId: '50233717', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 12, heightMm: 40, barcode: '01222281', sourceId: '80000351', barcodeEvidence: 'tag-capture' },
    { mediaType: 1, widthMm: 13, heightMm: 70, barcode: '6972842742674', sourceId: '50234177', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 14, heightMm: 20, barcode: '091625176', sourceId: '80045634', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 14, heightMm: 25, barcode: '010424779', sourceId: '58118004', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 14, heightMm: 30, barcode: '090223009', sourceId: '80006402', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 14, heightMm: 40, barcode: '08152233', sourceId: '80004091', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 14, heightMm: 50, barcode: '010424784', sourceId: '80004092', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 14, heightMm: 54, barcode: '06172280', sourceId: '51338418', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 14, heightMm: 60, barcode: '08042113', sourceId: '58117738', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 15, heightMm: 26, barcode: '6971501224582', sourceId: '80032608', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 15, heightMm: 30, barcode: '02282280', sourceId: '50230230', barcodeEvidence: 'tag-capture' },
    { mediaType: 1, widthMm: 15, heightMm: 50, barcode: '010424787', sourceId: '80032548', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 20, heightMm: 8, barcode: '091026183', sourceId: '80111310', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 20, heightMm: 10, barcode: '123025190', sourceId: '80113174', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 20, heightMm: 30, barcode: '6977388393373', sourceId: '80019751', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 20, heightMm: 40, barcode: '010924601', sourceId: '80019755', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 20, heightMm: 45, barcode: '040724038', sourceId: '80019754', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 20, heightMm: 75, barcode: '08042124', sourceId: '58118885', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 22, heightMm: 22, barcode: '041124118', sourceId: '80014717', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 25, heightMm: 10, barcode: '123025196', sourceId: '80113172', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 25, heightMm: 15, barcode: '123025197', sourceId: '80113129', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 25, heightMm: 30, barcode: '010924603', sourceId: '80019752', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 25, heightMm: 40, barcode: '08042121', sourceId: '58118687', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 25, heightMm: 50, barcode: '040924192', sourceId: '80019753', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 30, heightMm: 15, barcode: '123025201', sourceId: '80113128', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 30, heightMm: 40, barcode: '090223012', sourceId: '80049324', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 33, heightMm: 33, barcode: '111225133', sourceId: '80014718', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 40, heightMm: 10, barcode: '123025058', sourceId: '80113162', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 40, heightMm: 15, barcode: '123025206', sourceId: '80113161', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 40, heightMm: 20, barcode: '070626199', sourceId: '80032472', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 40, heightMm: 30, barcode: '070626200', sourceId: '80001799', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 40, heightMm: 40, barcode: '010424618', sourceId: '80032603', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 40, heightMm: 60, barcode: '022824258', sourceId: '80036381', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 40, heightMm: 80, barcode: '69522800001478', sourceId: '50229043', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 44, heightMm: 44, barcode: '040824050', sourceId: '80014719', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 45, heightMm: 20, barcode: '060723012', sourceId: '80032587', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 45, heightMm: 60, barcode: '010424623', sourceId: '50229046', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 50, heightMm: 15, barcode: '123025208', sourceId: '80113148', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 50, heightMm: 20, barcode: '11262110', sourceId: '80001173', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 50, heightMm: 30, barcode: '022824255', sourceId: '80000579', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 50, heightMm: 40, barcode: '03222123', sourceId: '80032570', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 50, heightMm: 50, barcode: '12222117', sourceId: '80001493', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 50, heightMm: 60, barcode: '060426251', sourceId: '80003856', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 50, heightMm: 70, barcode: '6971501220577', sourceId: '80032535', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 50, heightMm: 80, barcode: '071426081', sourceId: '80084611', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 60, heightMm: 40, barcode: '6977031215731', sourceId: '80013469', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 60, heightMm: 50, barcode: '080625209', sourceId: '80062856', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 60, heightMm: 60, barcode: '6978642800453', sourceId: '80000258', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 60, heightMm: 80, barcode: '060923009', sourceId: '80013475', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 70, heightMm: 40, barcode: '6971501224414', sourceId: '80000581', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 70, heightMm: 80, barcode: '6978061953617', sourceId: '80001426', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 70, heightMm: 100, barcode: '060226086', sourceId: '80013478', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 76, heightMm: 130, barcode: '061826162', sourceId: '80113260', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 80, heightMm: 40, barcode: '121024064', sourceId: '80071393', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 80, heightMm: 50, barcode: '060923019', sourceId: '80013485', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 80, heightMm: 80, barcode: '012226003', sourceId: '80060859', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 80, heightMm: 100, barcode: '072226110', sourceId: '80084603', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 80, heightMm: 160, barcode: '082024269', sourceId: '80026366', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 100, heightMm: 60, barcode: '121024115', sourceId: '80071479', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 100, heightMm: 70, barcode: '121024063', sourceId: '80071411', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 100, heightMm: 100, barcode: '121024118', sourceId: '80071394', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 100, heightMm: 150, barcode: '121024252', sourceId: '80071481', barcodeEvidence: 'catalogue-primary' },
    { mediaType: 1, widthMm: 100, heightMm: 200, barcode: '010526174', sourceId: '80113808', barcodeEvidence: 'catalogue-primary' },
];

export function findCatalogueEntry(params: MediaParameters): CatalogueEntry | undefined {
    return CATALOGUE.find(
        (e) => e.mediaType === params.mediaType && e.widthMm === params.widthMm && e.heightMm === params.heightMm,
    );
}

/** Rewrites the barcode string stored at fixed[32..] (lo). */
export function setBarcode(payload: Uint8Array, barcode: string): Uint8Array {
    if (!/^[0-9]{1,15}$/.test(barcode)) throw new Error('Unsupported catalogue barcode.');
    const { mutable, fixed } = decodePayload(payload);
    const terminator = fixed.indexOf(0, 32);
    if (terminator < 32 || terminator >= 48) throw new Error('Unsupported barcode string boundary.');
    for (let i = 32; i < terminator; i++) {
        if (fixed[i] < 48 || fixed[i] > 57) throw new Error('Unsupported source barcode.');
    }
    const newEnd = 32 + barcode.length;
    for (let i = terminator + 1; i <= newEnd; i++) {
        if (fixed[i] !== 0) throw new Error('Barcode edit would overwrite unknown nonzero bytes.');
    }
    fixed.fill(0, 32, Math.max(terminator, newEnd) + 1);
    fixed.set(Array.from(barcode, (ch) => ch.charCodeAt(0)), 32);
    return encodePayload(mutable, fixed);
}

/** Applies the catalogue barcode if the dimensions match (co). */
export function applyCatalogueBarcode(payload: Uint8Array): Uint8Array {
    const entry = findCatalogueEntry(payloadToParameters(payload));
    return entry ? setBarcode(payload, entry.barcode) : payload.slice();
}

// ---------------------------------------------------------------------------
// Dump parsing  (no, eo, to, Xa, Za)
// ---------------------------------------------------------------------------

export interface ChameleonExtra {
    ultralightSignature?: number[];
    ultralightVersion?: number[];
    ultralightCounters?: number[];
    [key: string]: unknown;
}

export interface ChameleonCard {
    id: string;
    name: string;
    uid: string;
    sak: number;
    atqa: number[];
    ats: number[];
    tag: number;
    color: string;
    data: number[][];
    extra: ChameleonExtra;
}

export interface ParsedDump {
    memory: Uint8Array;
    flipperText?: string;
    chameleonText?: string;
    importNotice?: string;
}

export function parseEml(text: string): Uint8Array {
    if (text.length > MAX_READ_SIZE) throw new Error('Target read is too large.');
    const lines = text
        .split(/\r?\n/)
        .map((line) => line.split('#')[0].trim())
        .filter(Boolean);
    if (![45, 135, 231].includes(lines.length) || lines.some((l) => !/^[0-9a-f]{8}$/i.test(l))) {
        throw new Error('Expected 45, 135 or 231 EML lines, each containing one four-byte hex page.');
    }
    return assertMemoryBcc(hexToBytes(lines.join('')));
}

export function parseFlipperText(text: string): ParsedDump {
    if (text.length > MAX_READ_SIZE) throw new Error('Target read is too large.');
    const fields = new Map<string, string>();
    const order: string[] = [];
    for (const line of text.split(/\r?\n/)) {
        if (!line.trim() || line.trimStart().startsWith('#')) continue;
        const match = /^([^:]+):\s*(.*?)\s*$/.exec(line);
        if (!match) throw new Error('Invalid Flipper record.');
        const key = match[1].trim();
        if (fields.has(key)) throw new Error(`Duplicate Flipper field: ${key}.`);
        fields.set(key, match[2]);
        order.push(key);
    }

    const requireField = (key: string): string => {
        const value = fields.get(key);
        if (value === undefined) throw new Error(`Missing Flipper field: ${key}.`);
        return value;
    };
    const requireEquals = (key: string, expected: string): void => {
        if (requireField(key) !== expected) throw new Error(`Unsupported Flipper ${key}; expected ${expected}.`);
    };
    const readHex = (key: string, length: number): Uint8Array => {
        const value = requireField(key);
        if (!new RegExp(`^[0-9a-fA-F]{2}(?:[ \\t]+[0-9a-fA-F]{2}){${length - 1}}$`).test(value)) {
            throw new Error(`Invalid or incomplete Flipper ${key}.`);
        }
        return hexToBytes(value.replace(/[ \t]/g, ''));
    };
    const readInt = (key: string, max: number): void => {
        const value = requireField(key);
        if (!/^\d+$/.test(value) || Number(value) > max) throw new Error(`Invalid Flipper ${key}.`);
    };

    requireEquals('Filetype', 'Flipper NFC device');
    requireEquals('Version', '4');
    requireEquals('Device type', 'NTAG/Ultralight');
    requireEquals('Data format version', '2');
    const spec = getTagType(requireField('NTAG/Ultralight type'));
    requireEquals('Pages total', String(spec.pages));
    requireEquals('Pages read', String(spec.pages));
    const headerUid = readHex('UID', 7);
    readHex('ATQA', 2);
    readHex('SAK', 1);
    readHex('Signature', 32);
    readHex('Mifare version', 8);
    for (let i = 0; i < 3; i++) {
        readInt(`Counter ${i}`, 16777215);
        readHex(`Tearing ${i}`, 1);
    }
    if (fields.has('Failed authentication attempts')) readInt('Failed authentication attempts', 4294967295);

    const memory = new Uint8Array(spec.pages * 4);
    for (let page = 0; page < spec.pages; page++) {
        memory.set(readHex(`Page ${page}`, 4), page * 4);
    }
    for (const key of fields.keys()) {
        if (/^Page\s/.test(key) && (!/^Page (?:0|[1-9][0-9]*)$/.test(key) || Number(key.slice(5)) >= spec.pages)) {
            throw new Error('Unexpected Flipper page.');
        }
    }
    assertMemoryBcc(memory);
    if (!bytesEqual(headerUid, Uint8Array.of(...memory.slice(0, 3), ...memory.slice(4, 8)))) {
        throw new Error('Flipper header UID does not match its memory pages.');
    }

    const canonical = [
        'Filetype',
        'Version',
        'Device type',
        'UID',
        'ATQA',
        'SAK',
        'Data format version',
        'NTAG/Ultralight type',
        'Signature',
        'Mifare version',
        ...Array.from({ length: 3 }, (_, i) => [`Counter ${i}`, `Tearing ${i}`]).flat(),
        'Pages total',
        'Pages read',
        ...Array.from({ length: spec.pages }, (_, i) => `Page ${i}`),
    ];
    if (canonical.some((key, i) => i > 0 && order.indexOf(key) <= order.indexOf(canonical[i - 1]))) {
        throw new Error('Flipper records must be in standard device-file order.');
    }
    return { memory, flipperText: text };
}

export function parseChameleonJson(text: string): ParsedDump {
    if (text.length > MAX_READ_SIZE) throw new Error('Target read is too large.');
    const card = JSON.parse(text) as ChameleonCard;
    const spec = TAG_TYPES.find((s) => card?.tag === s.chameleonId);
    const isByte = (v: unknown): boolean => Number.isInteger(v) && Number(v) >= 0 && Number(v) <= 255;
    const isByteArray = (v: unknown, length?: number): boolean =>
        Array.isArray(v) && (length === undefined || v.length === length) && v.every(isByte);

    if (
        !card ||
        typeof card !== 'object' ||
        !spec ||
        typeof card.id !== 'string' ||
        typeof card.name !== 'string' ||
        typeof card.uid !== 'string' ||
        !isByte(card.sak) ||
        !isByteArray(card.atqa, 2) ||
        !isByteArray(card.ats) ||
        typeof card.color !== 'string' ||
        !/^#[0-9a-f]{6}$/i.test(card.color) ||
        !Array.isArray(card.data) ||
        card.data.length !== spec.pages ||
        !card.data.every((page) => isByteArray(page, 4)) ||
        !card.extra ||
        typeof card.extra !== 'object' ||
        Array.isArray(card.extra)
    ) {
        throw new Error('Expected a complete NTAG213/215/216 Chameleon card with matching type and page count.');
    }

    for (const [key, length] of [
        ['ultralightSignature', 32],
        ['ultralightVersion', 8],
    ] as const) {
        if (key in card.extra && !isByteArray((card.extra as Record<string, unknown>)[key], length)) {
            throw new Error(`Invalid Chameleon ${key}.`);
        }
    }
    if ('ultralightCounters' in card.extra) {
        const counters = card.extra.ultralightCounters;
        if (
            !Array.isArray(counters) ||
            counters.length !== 3 ||
            !counters.every((c) => Number.isInteger(c) && c >= 0 && c <= 16777215)
        ) {
            throw new Error('Invalid Chameleon counters.');
        }
    }

    const memory = assertMemoryBcc(Uint8Array.from(card.data.flat()));
    if (!bytesEqual(parseUid(card.uid), extractUid({ memory }))) {
        throw new Error('Chameleon header UID does not match its memory pages.');
    }
    return { memory, chameleonText: text };
}

/** Detects format by file extension (no). */
export function parseDumpFile(bytes: Uint8Array, filename: string): ParsedDump {
    if (bytes.length > MAX_READ_SIZE) throw new Error('Target read is too large.');
    const ext = filename.toLowerCase().split('.').pop();
    if (ext === 'bin') {
        if (bytes.length === 184) {
            if (bytes.slice(180).some((b) => b !== 0)) {
                throw new Error(
                    'Unrecognised 184-byte dump: the four trailing bytes must be zero. Use a 180-byte NTAG213 memory read.',
                );
            }
            return {
                memory: assertMemoryBcc(bytes.slice(0, 180)),
                importNotice: 'Loaded 180 bytes of tag memory; ignored four trailing zero bytes. Raw output is 180 bytes.',
            };
        }
        return { memory: assertMemoryBcc(bytes) };
    }
    const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    if (ext === 'eml') return { memory: parseEml(text) };
    if (ext === 'nfc') return parseFlipperText(text);
    if (ext === 'json') return parseChameleonJson(text);
    throw new Error('Choose an NTAG213/215/216 .bin, .eml, .nfc or Chameleon .json file.');
}

/** Builds a Flipper device-file from memory + optional Chameleon metadata (Za). */
export function buildFlipperText(memory: Uint8Array, chameleon?: ChameleonCard): string {
    const spec = getTagType(tagTypeFromByteLength(memory.length));
    const extra = chameleon?.extra;
    const signature = extra?.ultralightSignature;
    const version = extra?.ultralightVersion;
    const counters = extra?.ultralightCounters;
    return [
        'Filetype: Flipper NFC device',
        'Version: 4',
        '# OpenRoll generated provisioning image, not an original tag capture.',
        `# Missing RF metadata uses an ${spec.id} preset. Missing signature is zero (unknown, not authentic).`,
        '# Missing NFC counters are zero; tearing flags BD are preset, not measured.',
        '# Physical writers must preserve UID, locks and unrelated factory state.',
        'Device type: NTAG/Ultralight',
        `UID: ${formatUidBytes(extractUid({ memory }))}`,
        `ATQA: ${formatUidBytes(Uint8Array.from(chameleon?.atqa ?? [0, 68]))}`,
        `SAK: ${formatUidBytes(Uint8Array.of(chameleon?.sak ?? 0))}`,
        'Data format version: 2',
        `NTAG/Ultralight type: ${spec.id}`,
        `Signature: ${formatUidBytes(Uint8Array.from(signature ?? Array(32).fill(0)))}`,
        `Mifare version: ${formatUidBytes(Uint8Array.from(version ?? [0, 4, 4, 2, 1, 0, spec.versionSize, 3]))}`,
        ...[0, 1, 2].flatMap((i) => [`Counter ${i}: ${counters?.[i] ?? 0}`, `Tearing ${i}: BD`]),
        `Pages total: ${spec.pages}`,
        `Pages read: ${spec.pages}`,
        ...Array.from({ length: spec.pages }, (_, i) => `Page ${i}: ${formatUidBytes(memory.slice(i * 4, i * 4 + 4))}`),
        '',
    ].join('\n');
}

// ---------------------------------------------------------------------------
// Export formats  (Ga, Ka, ro)
// ---------------------------------------------------------------------------

export type ExportFormatId = 'raw' | 'chameleon' | 'proxmark' | 'flipper';

export interface ExportFormatSpec {
    id: ExportFormatId;
    label: string;
    suffix: string;
    note: string;
}

export const EXPORT_FORMATS: ExportFormatSpec[] = [
    { id: 'raw', label: 'Raw NTAG213 (.bin)', suffix: '.bin', note: '180 bytes · full page image · app import workflows unverified.' },
    { id: 'chameleon', label: 'Chameleon card (.json)', suffix: '.json', note: 'Chameleon GUI card · 45 memory pages.' },
    { id: 'proxmark', label: 'Proxmark3 · page dump (.eml)', suffix: '.eml', note: '45 hex pages · writer workflow untested.' },
    { id: 'flipper', label: 'Flipper Zero (.nfc)', suffix: '.nfc', note: 'NTAG213 device file · writer workflow untested.' },
];

export function exportFormatsForTag(tagType: TagTypeId): ExportFormatSpec[] {
    return EXPORT_FORMATS.map((f) => ({
        ...f,
        label: f.label.replaceAll('NTAG213', tagType),
        note: f.note
            .replaceAll('NTAG213', tagType)
            .replaceAll('180 bytes', `${getTagType(tagType).pages * 4} bytes`)
            .replaceAll('45', String(getTagType(tagType).pages)),
    }));
}

export interface ExportResult {
    bytes: Uint8Array;
    suffix: string;
    assumptions: string[];
}

/**
 * The core export routine (ro). Merges the ORF1 payload into the target
 * memory (bitwise, per the write mask) and serialises to the chosen format.
 */
export function exportTagFile(
    format: ExportFormatId,
    orf1: Uint8Array,
    payload: Uint8Array,
    uid: Uint8Array,
    targetDump: ParsedDump | undefined,
    tagType: TagTypeId = 'NTAG213',
): ExportResult {
    const spec = getTagType(tagType);
    validateOrf1(orf1, payload, uid);
    const formatSpec = EXPORT_FORMATS.find((f) => f.id === format);
    if (!formatSpec) throw new Error('Unsupported export format.');

    const base: ParsedDump = targetDump?.flipperText
        ? parseFlipperText(targetDump.flipperText)
        : targetDump?.chameleonText
            ? parseChameleonJson(targetDump.chameleonText)
            : { memory: targetDump ? assertMemoryBcc(targetDump.memory) : blankTagPreset(uid, tagType) };

    if (tagTypeFromByteLength(base.memory.length) !== tagType) {
        throw new Error('Target dump type does not match the selected tag type.');
    }

    const chameleonCard: ChameleonCard | undefined = base.chameleonText ? JSON.parse(base.chameleonText) : undefined;

    const assumptions: string[] = [];
    if (!targetDump) {
        assumptions.push(
            `UID-only: non-payload memory uses a blank ${tagType} preset, not a read of this tag. Preserve physical UID, lock bits and unrelated factory state when writing.`,
        );
    }
    if (format === 'flipper' && !base.flipperText) {
        assumptions.push(
            `Flipper metadata uses ${tagType} defaults where unavailable. The zero signature means unknown; NFC counters and tearing flags are placeholders, not a captured chip identity.`,
        );
    }
    if (format === 'chameleon' && !chameleonCard) {
        assumptions.push(
            `Chameleon RF selection uses ${tagType} defaults (ATQA 00 44, SAK 00). No originality signature or hardware counters are invented.`,
        );
    }

    const orf1Memory = orf1.slice(4, 184);
    const writeMask = orf1.slice(364);
    if (!bytesEqual(base.memory.slice(0, 9), orf1Memory.slice(0, 9))) {
        throw new Error('Target read UID does not match the entered UID.');
    }

    const merged = base.memory.slice();
    for (let offset = 0; offset < 180; offset++) {
        if (!writeMask[offset]) continue;
        const targetOffset = offset >= 164 ? spec.configPage * 4 + offset - 164 : offset;
        merged[targetOffset] = (merged[targetOffset] & ~writeMask[offset]) | (orf1Memory[offset] & writeMask[offset]);
    }

    if (format === 'raw') {
        return { bytes: merged, suffix: formatSpec.suffix, assumptions };
    }

    if (format === 'chameleon') {
        const card = {
            id: `openroll-${bytesToHex(uid)}-${crc32(merged).toString(16).padStart(8, '0')}`,
            uid: formatUidBytes(uid),
            sak: chameleonCard?.sak ?? 0,
            atqa: chameleonCard?.atqa ?? [0, 68],
            ats: chameleonCard?.ats ?? [],
            name: `OpenRoll ${formatUidBytes(uid)}`,
            tag: spec.chameleonId,
            color: chameleonCard?.color ?? '#244c40',
            data: Array.from({ length: spec.pages }, (_, i) => Array.from(merged.slice(i * 4, i * 4 + 4))),
            extra: chameleonCard?.extra ?? {},
        };
        const text = JSON.stringify(card, null, 2) + '\n';
        if (!bytesEqual(parseChameleonJson(text).memory, merged)) {
            throw new Error('Chameleon export validation failed.');
        }
        return { bytes: new TextEncoder().encode(text), suffix: formatSpec.suffix, assumptions };
    }

    if (format === 'proxmark') {
        const text =
            Array.from({ length: spec.pages }, (_, i) => bytesToHex(merged.slice(i * 4, i * 4 + 4)).toUpperCase()).join(
                '\n',
            ) + '\n';
        return { bytes: new TextEncoder().encode(text), suffix: formatSpec.suffix, assumptions };
    }

    // flipper
    const flipperBase = base.flipperText ?? buildFlipperText(merged, chameleonCard);
    const text = flipperBase.replace(
        /^([ \t]*Page (\d+):)[ \t]*[^\r\n]*(\r?)$/gm,
        (_match, prefix: string, pageNum: string, cr: string) =>
            `${prefix} ${(bytesToHex(merged.slice(Number(pageNum) * 4, Number(pageNum) * 4 + 4)).toUpperCase().match(/../g) ?? []).join(' ')}${cr}`,
    );
    if (!bytesEqual(parseFlipperText(text).memory, merged)) {
        throw new Error('Flipper export page validation failed.');
    }
    return { bytes: new TextEncoder().encode(text), suffix: formatSpec.suffix, assumptions };
}

// ---------------------------------------------------------------------------
// Top-level orchestrator  (component `ge` handler)
// ---------------------------------------------------------------------------

export interface GenerateInput {
    mediaType: number;
    widthMm: number;
    heightMm: number;
    gapMm: number;
    nominalQuantity: number;
    uid: string;
    tagType?: TagTypeId;
    format?: ExportFormatId;
    targetDump?: ParsedDump;
}

export interface GenerateResult extends ExportResult {
    uid: string;
    tagType: TagTypeId;
    profile: string;
    custom: boolean;
    fromRead: boolean;
    filename: string;
}

export async function generateTagFile(input: GenerateInput): Promise<GenerateResult> {
    const tagType = input.tagType ?? 'NTAG213';
    const format = input.format ?? 'raw';
    const uid = parseUid(input.uid);

    // Continuous media has no fixed length/gap (oe).
    const effective = { ...input };
    if (effective.mediaType === 3) {
        effective.heightMm = 0;
        effective.gapMm = 0;
    }

    const params: MediaParameters = {
        mediaType: effective.mediaType,
        widthMm: effective.widthMm,
        heightMm: effective.heightMm,
        gapMm: effective.gapMm,
        nominalQuantity: effective.nominalQuantity,
        usageLimit: computeUsageLimit(effective.nominalQuantity),
    };
    validateParameters(params);

    if (input.targetDump && bytesToHex(uid) !== bytesToHex(extractUid(input.targetDump))) {
        throw new Error('UID does not match the optional dump. Correct the UID or remove the dump.');
    }
    if (input.targetDump && tagTypeFromByteLength(input.targetDump.memory.length) !== tagType) {
        throw new Error('Tag type does not match the optional dump. Select its type or remove the dump.');
    }

    const template = await loadTemplate(PRINTER_PROFILE.id, ROLL_PROFILE.id);
    const payload = applyCatalogueBarcode(parametersToPayload(template, params));

    const orf1 = buildOrf1(payload, uid);
    validateOrf1(orf1, payload, uid);

    const exported = exportTagFile(format, orf1, payload, uid, input.targetDump, tagType);

    const custom = isCustomParameters(params);
    const mediaLabel = MEDIA_TYPES.find((m) => m.value === params.mediaType)?.label ?? 'Media';
    const dims =
        params.mediaType === 3
            ? `${params.widthMm} mm wide · continuous`
            : `${params.widthMm} × ${params.heightMm} mm`;
    const profile = `${mediaLabel} · ${dims}`;

    const profilePart = custom ? 'niimbot-custom' : ROLL_PROFILE.id;
    const tagPart = tagType === 'NTAG213' ? '' : `-${tagType.toLowerCase()}`;
    const filename = `openroll-${profilePart}${tagPart}-${bytesToHex(uid)}${exported.suffix}`;

    return {
        ...exported,
        uid: bytesToHex(uid),
        tagType,
        profile,
        custom,
        fromRead: Boolean(input.targetDump),
        filename,
    };
}