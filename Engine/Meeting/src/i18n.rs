#[derive(Clone, Copy)]
pub enum Lang { Zh, En }
impl Lang {
 pub fn is_en(self) -> bool { matches!(self, Self::En) }
 pub fn pick<'a>(self, zh: &'a str, en: &'a str) -> &'a str { if self.is_en() { en } else { zh } }
}
pub fn tr<'a>(zh: &'a str, _en: &'a str) -> &'a str { zh }
