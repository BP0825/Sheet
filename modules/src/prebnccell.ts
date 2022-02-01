/*! sheetjs (C) 2013-present SheetJS -- http://sheetjs.com */
import { CellObject } from '../../';
import { u8_to_dataview, popcnt } from './util';

function parseit(buf: Uint8Array, sst: string[], rsst: string[], version: number): CellObject {
  var dv = u8_to_dataview(buf);
  var ctype = buf[version == 4 ? 1 : 2];

  /* TODO: find the correct field position of number formats, formulae, etc */
  var flags = dv.getUint32(4, true);
  var data_offset = 12 + popcnt(flags & 0x0D8E) * 4;

  var ridx = -1, sidx = -1, ieee = NaN, dt = new Date(2001, 0, 1);
  if(flags & 0x0200) { ridx = dv.getUint32(data_offset,  true); data_offset += 4; }
  data_offset += popcnt(flags & 0x3000) * 4;
  if(flags & 0x0010) { sidx = dv.getUint32(data_offset,  true); data_offset += 4; }
  if(flags & 0x0020) { ieee = dv.getFloat64(data_offset, true); data_offset += 8; }
  if(flags & 0x0040) { dt.setTime(dt.getTime() +  dv.getFloat64(data_offset, true) * 1000); data_offset += 8; }

  var ret: CellObject;
  switch(ctype) {
    case 0: break; // return { t: "z" }; // blank?
    case 2: ret = { t: "n", v: ieee }; break; // number
    case 3: ret = { t: "s", v: sst[sidx] }; break; // string
    case 5: ret = { t: "d", v: dt }; break; // date-time
    case 6: ret = { t: "b", v: ieee > 0 }; break; // boolean
    case 7: ret = { t: "n", v: ieee }; break; // duration in seconds TODO: emit [hh]:[mm] style format with adjusted value
    case 8: ret = { t: "e", v: 0}; break; // "formula error" TODO: enumerate and map errors to csf equivalents
    case 9: { // "automatic"?
      if(ridx > -1) ret = { t: "s", v: rsst[ridx] };
      else if(sidx > -1) ret = { t: "s", v: sst[sidx] };
      else if(!isNaN(ieee)) ret = { t: "n", v: ieee };
      else throw new Error(`Unsupported cell type ${buf.slice(0,4)}`);
    } break;
    default: throw new Error(`Unsupported cell type ${buf.slice(0,4)}`);
  }
  /* TODO: Some fields appear after the cell data */

  return ret;
}

function parse(buf: Uint8Array, sst: string[], rsst: string[]): CellObject {
  var version = buf[0]; // numbers 3.5 uses "3", 6.x - 11.x use "4"
  switch(version) {
    case 3: case 4: return parseit(buf, sst, rsst, version);
    default: throw new Error(`Unsupported pre-BNC version ${version}`);
  }
}

export { parse };