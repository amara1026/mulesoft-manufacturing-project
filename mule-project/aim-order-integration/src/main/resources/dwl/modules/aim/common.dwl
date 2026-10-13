%dw 2.0
import leftPad from dw::core::Strings

/** SAP ALPHA conversion: numeric IDs are left-padded with zeros (100234 -> 0000100234). */
fun sapAlpha(id: String, len: Number = 10): String =
  if (id matches /^[0-9]+$/) leftPad(id, len, "0") else id

/** Business date (no time zone) to SAP DATS format. */
fun toSapDate(d: Date): String = d as String { format: "yyyyMMdd" }

/** External (ISO-like) UoM to SAP internal UoM. Confirm codes with the SAP SD team. */
var uomToSap = { "EA": "ST", "PC": "ST", "KG": "KG", "M": "M", "BOX": "KAR" }
fun sapUom(u: String): String = uomToSap[u] default u

/** ISO-8601 timestamp with offset, used in events and error bodies. */
fun isoNow(): String = now() as String { format: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX" }
