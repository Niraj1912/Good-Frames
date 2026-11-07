/// What the app remembers about how a photo looks, so look-alikes can be
/// found without opening photos again: a 64-bit "fingerprint" and a score
/// for how sharp it is. See `Similarity` for how they're made and compared.
class Fingerprint {
  const Fingerprint(this.hash, this.sharpness, [this.colour = 0x808080]);

  /// The photo's difference hash (dHash).
  final int hash;

  /// The photo's average colour, as 0xRRGGBB. A fingerprint sees only light
  /// and dark, so two photos laid out alike but in different colours (a
  /// red screenshot and a blue one) have the same hash; the colour tells
  /// them apart.
  final int colour;

  /// How crisp the photo's edges are, from 0 (flat) to about 0.3 (very
  /// busy). Among shots of the same scene, the blurred ones score lowest.
  final double sharpness;

  /// A photo with less detail than this is [isFlat].
  static const flatBelow = 0.004;

  /// Too plain to compare: a blank wall or a solid colour has no shape for
  /// a fingerprint to describe, so any two of them would look alike.
  bool get isFlat => sharpness < flatBelow;

  @override
  bool operator ==(Object other) =>
      other is Fingerprint &&
      other.hash == hash &&
      other.sharpness == sharpness &&
      other.colour == colour;

  @override
  int get hashCode => Object.hash(hash, sharpness, colour);
}

/// A [Fingerprint] as saved in the database, with what it was made from.
class SavedFingerprint {
  const SavedFingerprint(this.photoId, this.stamp, this.fingerprint);

  final String photoId;

  /// The photo's date when this was made. If the photo's date is different
  /// now, the photo was changed and the fingerprint is out of date.
  final int stamp;

  final Fingerprint fingerprint;
}
